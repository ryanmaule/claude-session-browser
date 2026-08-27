#!/bin/bash
# Baut ein DMG aus dem App-Bundle: App drin, Verknuepfung nach /Applications
# daneben, damit man das eine auf das andere zieht.
#
# Nutzung:  ./make-macos-dmg.sh
# Ergebnis: dist/ClaudeSessionBrowser-macOS.dmg
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/bin/python3 -c 'import json;print(json.load(open("version.json"))["version"])')"
STAGE="$(mktemp -d)/dmg"
OUT="$SRC/dist"
DMG="$OUT/ClaudeSessionBrowser-macOS.dmg"

mkdir -p "$STAGE" "$OUT"

echo "==> App bauen"
"$SRC/make-macos-app.sh" "$STAGE" >/dev/null

echo "==> Ziehziel danebenlegen"
ln -s /Applications "$STAGE/Applications"

echo "==> DMG schreiben"
rm -f "$DMG"
hdiutil create -volname "Claude Session Browser" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

echo "==> Fertig: $DMG  ($(du -h "$DMG" | cut -f1), Version $VERSION)"
echo
echo "Die App ist ad-hoc signiert, nicht notarisiert. macOS blockiert sie beim"
echo "ersten Start deshalb; freigeben unter Systemeinstellungen > Datenschutz"
echo "& Sicherheit, dort steht sie nach dem Startversuch mit einem Knopf."
