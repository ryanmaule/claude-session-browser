#!/bin/bash
# Build "Claude Session Browser.app" for macOS and install it.
#
# CFBundleExecutable is a small native launcher compiled here, which starts
# claude_sessions.py through Py_BytesMain. That matters more than it looks:
# LaunchServices registers the process it starts as the application, and a
# shell script that exec's a different binary (or starts one and exits) leaves
# that registration pointing at something else. The window and the Dock icon
# survive that, but the menu bar refuses the app's status item -- the tray icon
# simply never appears when launched from the Finder, while a start from the
# terminal works fine. Python therefore has to run in the very process macOS
# launched.
#
# Requires the Xcode command line tools (xcrun clang) and a Python *framework*
# build with headers -- Homebrew's python@3.x has both.
#
# By default everything is copied into the bundle, so this checkout can be
# moved or deleted afterwards; --dev links back here instead and picks up every
# change on the next launch.
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
BUNDLE_ID="com.claudesessionbrowser.app"   # muss zur Info.plist passen
VENV="$SRC/.venv/bin/python"
VERSION="$(/usr/bin/python3 -c 'import json;print(json.load(open("version.json"))["version"])' 2>/dev/null || echo 0)"

if [ ! -x "$VENV" ]; then
    echo "Error: no virtualenv at $VENV"
    echo "Create one first:"
    echo "  /usr/bin/env python3 -m venv .venv && ./.venv/bin/pip install pywebview bleak pillow pystray"
    echo
    echo "Optional: brew install python-tk@3.13 -- without Tk the limit-reset"
    echo "toast and monitor detection stay quiet, and there is no desktop"
    echo "buddy. Everything else, the Clawdmeter included, works without it."
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
    <key>CFBundleExecutable</key>        <string>$APP_EXEC</string>
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

echo "==> Native Python launcher"
# CFBundleExecutable must be the long-lived Mach-O process which owns NSApp.
# A shell script is not a proper LaunchServices application executable; and
# having that script exec or orphan a different binary leaves LaunchServices
# tracking a process which no longer matches (or no longer exists). Build a
# tiny native launcher linked to the venv's Python framework instead. Python
# then runs inside the registered process: no shell, child, or executable
# replacement separates NSApplication from the identity LaunchServices owns.
BASE="$("$VENV" -c 'import sys; print(sys.base_prefix)')"
PYVER="$("$VENV" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
PYTHON_DYLIB="$BASE/Python"
PYTHON_INCLUDE="$BASE/include/python$PYVER"
if [ ! -f "$PYTHON_DYLIB" ] || [ ! -d "$PYTHON_INCLUDE" ]; then
    echo "Error: Python framework development files not found under $BASE"
    echo "The native launcher links against libPython, so the venv has to be"
    echo "built on a framework install that ships headers -- e.g."
    echo "  brew install python@3.13"
    echo "The Python from the Xcode command line tools does not qualify."
    exit 1
fi
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
    for f in "$SRC"/*.py "$SRC"/version.json "$SRC"/claude_sessions.ico; do
        [ -e "$f" ] && cp "$f" "$APP/Contents/Resources/app/"
    done
    # docs/ traegt die Bilder, auf die die Oberflaeche verweist.
    [ -d "$SRC/docs" ] && cp -R "$SRC/docs" "$APP/Contents/Resources/app/docs"
    RUNDIR="$APP/Contents/Resources/app"
fi

LAUNCH_SRC="$(mktemp -d)/csb-launcher.c"
cat > "$LAUNCH_SRC" <<LAUNCHER
#include <Python.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *script = "$RUNDIR/claude_sessions.py";
    int app_launch = argc == 1;
    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "-psn_", 5) != 0) {
            app_launch = 0;
            break;
        }
    }
    if (!app_launch) {
        return Py_BytesMain(argc, argv);
    }
    char *python_argv[] = {argv[0], (char *)script, NULL};
    return Py_BytesMain(2, python_argv);
}
LAUNCHER
xcrun clang -Os -I"$PYTHON_INCLUDE" "$LAUNCH_SRC" "$PYTHON_DYLIB" \
    -o "$APP/Contents/MacOS/$APP_EXEC"

echo "==> Signing"
# Sign the actual long-lived CFBundleExecutable, then seal the whole bundle.
codesign --force -s - --identifier "$BUNDLE_ID" \
    "$APP/Contents/MacOS/$APP_EXEC" 2>/dev/null || \
    echo "  warning: could not sign the launcher; the app may refuse to start"

# Und dann das ganze Bundle. Das ist fuer einen konsistenten LaunchServices-
# Eintrag noetig, aber nicht ausreichend: CFBundleExecutable muss ausserdem
# der echte, langlebige Mach-O-Prozess sein (siehe nativer Starter oben).
codesign --force --deep -s - --identifier "$BUNDLE_ID" "$APP" 2>/dev/null || \
    echo "  warning: could not sign the bundle; the menu bar icon may not appear"

# Replacing the bundle leaves LaunchServices pointing at what used to be here,
# and `open -a` then says it cannot find the app at all. Re-register it.
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP" 2>/dev/null || true

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
