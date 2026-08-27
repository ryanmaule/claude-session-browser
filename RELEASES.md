# Releases

All user-visible changes to this app are documented here.
Entries are written in plain English for non-technical users.

Format: `## v<version> — <Month Day, Year>` blocks, reverse chronological, bullet points.

Versions come from `version.json` at the time `/release` is run. This is the macOS
fork, so versions carry a fourth part (`1.4.0.6`) marking the Mac release on top of
the upstream version it sits on.

---

## v1.4.0.8 — August 27, 2026
- Fixed a short API outage being announced as a usage limit. Three different things stop Claude working — a spent limit, an expired login, an overloaded API — and they all show the same cross face, because there is only one cross face. They were also all announced with the same words, so half a minute of the API being busy reached you as "your Claude limit is back". Each one now says what actually happened — the notification and, on Windows, the card that comes with it.

## v1.4.0.7 — August 27, 2026
- Fixed Clawd turning angry over usage limits that never happened. A command that failed counted as an error, and the app then searched that command's output for words — so output containing "auth" was enough for it to announce that your login had expired. On one morning it did this twelve times. Only what Claude itself records as an API error counts now; the output of your own commands never does.

## v1.4.0.6 — August 27, 2026
- Fixed the app quitting by itself on macOS. It happened about a minute after Clawd turned angry about a usage limit, and it left nothing behind — no error, no window, just a missing app. Reopening it always brought everything back, which made it easy to mistake for something your Claude account was doing.
- Notifications now come from Claude Session Browser. They used to arrive under the name and icon of "Script Editor", a macOS scripting tool, which made them look like they came from something else entirely. They also now have their own entry in System Settings → Notifications, so you can control or silence them there.
- The "limit is back" notification now arrives on macOS even with the menu-bar icon turned off. Previously that message reached you only if the icon was running.
- Corrected the settings text for limit notifications, which described them as a Windows-only feature.
- Building on macOS no longer needs the optional `python-tk` package.
