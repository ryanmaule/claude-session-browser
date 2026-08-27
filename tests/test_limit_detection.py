#!/usr/bin/env python3
"""Was zaehlt als Limit -- und vor allem, was nicht.

Der Buddy hat den ganzen 27.08. ueber Limits gemeldet, die es nie gab: zwoelf
Stueck an einem Vormittag, alle aus *Tool-Ergebnissen*. Ein fehlgeschlagenes
Kommando ist strukturell ein Fehler, und danach wurde seine Ausgabe nach
Woertern durchsucht -- ein Hostname mit "auth" darin reichte, und die App
behauptete, die Anmeldung sei abgelaufen.

Tool-Ausgabe ist fremder Text. Nur was Claude selbst als API-Fehler abgelegt
hat, darf hier zaehlen.

Lauf:  ./.venv/bin/python tests/test_limit_detection.py
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import claude_sessions as cs  # noqa: E402


def detect(line):
    """Genau der Weg, den die App geht -- keine nachgebaute Logik."""
    tmp = tempfile.mkdtemp()
    proj = os.path.join(tmp, "p")
    os.makedirs(proj)
    with open(os.path.join(proj, "session.jsonl"), "w") as fh:
        fh.write(json.dumps(line) + "\n")
    st = cs._latest_jsonl_status(tmp)
    return st["is_limit"], st["limit_type"]


def tool_result(text, is_error=True):
    """Ein Tool-Ergebnis, wie Claude Code es schreibt."""
    return {
        "type": "user",
        "message": {"role": "user", "content": [
            {"type": "tool_result", "content": text, "is_error": is_error}]},
        "toolUseResult": {"stdout": text},
    }


def api_error(text, status=429, err="rate_limit"):
    """Eine echte Limit-Meldung von Claude Code."""
    return {
        "type": "assistant", "isApiErrorMessage": True,
        "apiErrorStatus": status, "error": err,
        "message": {"role": "assistant", "model": "<synthetic>",
                    "stop_reason": "stop_sequence",
                    "content": [{"type": "text", "text": text}]},
    }


MUST_NOT_FIRE = [
    ("blocked command naming an auth host", tool_result(
        "<tool_use_error>Blocked: gh pr checks -R cam4labs/auth.cam4labs.app"
        "</tool_use_error>")),
    ("failed command whose output says auth", tool_result(
        "curl: (22) 401 Unauthorized -- run gcloud auth login")),
    ("a session that greps its own limit code", tool_result(
        "claude_sessions.py:485: r\"(?:you'?ve (?:reached|hit) your "
        "(?:5.?hour|weekly) limit)\"")),
    ("a transcript quoting the limit wording", tool_result(
        "You've reached your 5-hour limit -- that is the string we match on")),
    ("rate and limit as ordinary words", tool_result(
        "rate limiting the retries so we do not hit the API limit")),
    ("a plain failing command", tool_result("ls: nope: No such file or directory")),
    ("assistant text discussing limits", {
        "type": "assistant",
        "message": {"role": "assistant", "stop_reason": "end_turn",
                    "content": [{"type": "text", "text":
                                 "You've hit your session limit is the phrase "
                                 "the regex looks for."}]}}),
]

MUST_FIRE = [
    ("real 5h limit (429)", api_error(
        "You've hit your session limit · resets 11:10pm (America/Toronto)"),
     "rate_limited"),
    ("real limit without the usual wording", api_error(
        "Something new Anthropic has not written yet"), "rate_limited"),
    ("expired login (401)", api_error(
        "OAuth token revoked, please run /login", status=401,
        err="authentication_error"), "auth_required"),
    ("overloaded API (529)", api_error(
        "API Error: Overloaded", status=529, err="overloaded_error"),
     "api_overloaded"),
]

fails = []
for name, line in MUST_NOT_FIRE:
    fired, kind = detect(line)
    if fired:
        fails.append(f"FALSE POSITIVE: {name} -> {kind}")
for name, line, expected in MUST_FIRE:
    fired, kind = detect(line)
    if not fired:
        fails.append(f"MISSED: {name} (expected {expected})")
    elif kind != expected:
        fails.append(f"WRONG KIND: {name} -> {kind}, expected {expected}")

total = len(MUST_NOT_FIRE) + len(MUST_FIRE)
if fails:
    print(f"FAIL ({len(fails)} of {total})")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print(f"PASS ({total} cases: {len(MUST_NOT_FIRE)} must stay quiet, "
      f"{len(MUST_FIRE)} must fire)")
