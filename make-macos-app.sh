#!/bin/bash
# Build "Claude Session Browser.app" for macOS and install it.
#
# The bundle is a thin wrapper: it carries the icon, the name macOS shows in
# the Dock and in Login Items, and a launcher that starts claude_sessions.py
# from this checkout using the virtualenv next to it. Nothing is copied, so a
# `git pull` here is picked up on the next launch -- but moving or deleting
# this directory breaks the installed app. Re-run the script after moving it.
#
# Usage:
#   ./make-macos-app.sh                 # install into /Applications
#   ./make-macos-app.sh ~/Applications  # or wherever you like
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
# Standardmaessig kommt alles mit ins Bundle: die App soll auch dann noch
# starten, wenn dieses Verzeichnis umbenannt, verschoben oder geloescht wird.
# --dev verweist stattdessen hierher, dann wirkt jede Aenderung sofort -- aber
# das Bundle haengt an diesem Pfad.
MODE=standalone
ARGS=()
for a in "$@"; do
    case "$a" in
        --dev)        MODE=dev ;;
        --standalone) MODE=standalone ;;
        *)            ARGS+=("$a") ;;
    esac
done
DEST="${ARGS[0]:-/Applications}"
APP="$DEST/Claude Session Browser.app"
APP_EXEC="Claude Session Browser"   # Dock/Login-Items label = this file name
VENV="$SRC/.venv/bin/python"
VERSION="$(/usr/bin/python3 -c 'import json;print(json.load(open("version.json"))["version"])' 2>/dev/null || echo 0)"

if [ ! -x "$VENV" ]; then
    echo "Error: no virtualenv at $VENV"
    echo "Create one first:"
    echo "  /usr/bin/env python3 -m venv .venv && ./.venv/bin/pip install pywebview bleak pillow pystray"
    exit 1
fi
if [ ! -w "$DEST" ]; then
    echo "Error: $DEST is not writable. Pass a different target, e.g."
    echo "  $0 ~/Applications"
    exit 1
fi

echo "==> Icon"
# Only sizes the 256px source actually covers -- upscaling to 512/1024 would
# just produce a soft icon, and macOS scales down from 256 well enough.
ICONSET="$(mktemp -d)/appicon.iconset"
mkdir -p "$ICONSET"
make_png() { sips -z "$1" "$1" "$SRC/docs/logo.png" --out "$ICONSET/$2" >/dev/null; }
make_png 16  icon_16x16.png
make_png 32  icon_16x16@2x.png
make_png 32  icon_32x32.png
make_png 64  icon_32x32@2x.png
make_png 128 icon_128x128.png
make_png 256 icon_128x128@2x.png
make_png 256 icon_256x256.png

echo "==> Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/appicon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Claude Session Browser</string>
    <key>CFBundleDisplayName</key>       <string>Claude Session Browser</string>
    <key>CFBundleIdentifier</key>        <string>com.claudesessionbrowser.app</string>
    <key>CFBundleExecutable</key>        <string>launcher</string>
    <key>CFBundleIconFile</key>          <string>appicon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Ohne diese Texte beendet macOS die App in dem Moment, in dem sie
         Bluetooth oder AppleScript anfasst -- SIGABRT aus der TCC-Ecke, ohne
         dass ein Dialog erscheint. Aus dem Terminal gestartet faellt das nicht
         auf: dann haengt die Berechtigung am Terminal. Aus dem Finder ist die
         App selbst zustaendig und muss sagen, wofuer sie das braucht. -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Der Clawdmeter wird über Bluetooth mit deiner Claude-Auslastung versorgt.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Der Clawdmeter wird über Bluetooth mit deiner Claude-Auslastung versorgt.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Erkennt an offenen Terminal-Fenstern, ob Claude Code gerade läuft.</string>
    <key>LSMinimumSystemVersion</key>    <string>10.13</string>
</dict>
</plist>
PLIST

echo "==> Interpreter"
# The Dock and Login Items show whichever bundle owns the RUNNING executable,
# and they label it with that executable's file name. Exec'ing the Homebrew
# python leaves the app looking like "Python" with the generic rocket icon, so
# the interpreter is copied in here and named after the app.
#
# It has to be the framework binary, not bin/python3.13: that one is a stub
# that re-execs the framework copy, which hands the identity straight back.
#
# A copied venv interpreter no longer finds its virtualenv (it looks for
# ../pyvenv.cfg next to itself), so the venv is restated in bundle terms --
# pyvenv.cfg beside MacOS/, lib/ pointed at the real one. Nothing is
# duplicated; the packages stay in the checkout.
BASE="$("$VENV" -c 'import sys; print(sys.base_prefix)')"
PYVER="$("$VENV" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
FRAMEWORK_PY="$BASE/Resources/Python.app/Contents/MacOS/Python"
[ -x "$FRAMEWORK_PY" ] || FRAMEWORK_PY="$BASE/bin/python$PYVER"
if [ ! -x "$FRAMEWORK_PY" ]; then
    echo "Error: no interpreter found under $BASE"
    exit 1
fi
cp "$FRAMEWORK_PY" "$APP/Contents/MacOS/$APP_EXEC"
cat > "$APP/Contents/pyvenv.cfg" <<CFG
home = $BASE/bin
include-system-site-packages = false
version = $("$VENV" -c 'import platform; print(platform.python_version())')
CFG
mkdir -p "$APP/Contents/lib"
if [ "$MODE" = dev ]; then
    ln -sfn "$SRC/.venv/lib/python$PYVER" "$APP/Contents/lib/python$PYVER"
    RUNDIR="$SRC"
    echo "  dev mode: running from $SRC"
else
    echo "==> Copying app and packages into the bundle"
    cp -R "$SRC/.venv/lib/python$PYVER" "$APP/Contents/lib/python$PYVER"
    mkdir -p "$APP/Contents/Resources/app"
    for f in "$SRC"/*.py "$SRC"/version.json; do
        [ -e "$f" ] && cp "$f" "$APP/Contents/Resources/app/"
    done
    # docs/ traegt die Bilder, auf die die Oberflaeche verweist.
    [ -d "$SRC/docs" ] && cp -R "$SRC/docs" "$APP/Contents/Resources/app/docs"
    RUNDIR="$APP/Contents/Resources/app"
fi

cat > "$APP/Contents/MacOS/launcher" <<LAUNCHER
#!/bin/bash
# Only one copy at a time: a second launch brings the running one forward.
# _acquire_single_instance() is a Windows-only guard, so without this two apps
# would run and both drive the Clawdmeter over BLE.
#
# Match on this bundle's own interpreter, not on "claude_sessions.py": that
# string turns up in any shell that happens to mention the file, and a false
# match here means a launch that quietly does nothing.
#
# Raising the window goes through System Events, addressing the process. The
# obvious \`tell application "Claude Session Browser" to activate\` must not be
# used: for an app that is NOT running that asks LaunchServices to start it --
# which is this launcher, which would then wait for itself. That deadlocks with
# a Dock icon, no window, and "Application Not Responding".
SELF="\$(dirname "\$0")/$APP_EXEC"
if /usr/bin/pgrep -f "\$SELF" >/dev/null 2>&1; then
    /usr/bin/osascript -e 'tell application "System Events" to set frontmost of the first process whose name is "$APP_EXEC" to true' >/dev/null 2>&1 || true
    exit 0
fi
cd "$RUNDIR"
exec "\$SELF" claude_sessions.py
LAUNCHER
chmod +x "$APP/Contents/MacOS/launcher"

echo "==> Signing"
# The copied interpreter carries a signature made for its old home. Left as it
# is, macOS kills the process on launch with SIGTRAP (exit 133) and no message
# of any kind. An ad-hoc signature is enough for a locally built app.
codesign --force -s - "$APP/Contents/MacOS/$APP_EXEC" 2>/dev/null || \
    echo "  warning: could not sign the interpreter; the app may refuse to start"

# Drop the quarantine flag so Finder does not refuse a locally built bundle.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
touch "$APP"

echo "==> Installed: $APP"
if [ "$MODE" = dev ]; then
    echo "    Runs from: $SRC  (--dev: moving or deleting it breaks the app)"
else
    echo "    Self-contained — this checkout can be moved or deleted."
    echo "    Re-run this script after changing the source to update the app."
fi
echo
echo "Start it from Spotlight or Launchpad. To have it start at login:"
echo "  System Settings > General > Login Items > + > Claude Session Browser"
