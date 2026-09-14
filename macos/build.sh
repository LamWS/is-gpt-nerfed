#!/bin/sh
# Build DoesGPTCheat.app (menu bar app) with SwiftPM and assemble an ad-hoc signed bundle.
# Usage: ./macos/build.sh [--run]     (needs Xcode 26+ / macOS 26 SDK)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
swift build -c release 2>&1 | grep -v '^\[' || true
BIN="$(swift build -c release --show-bin-path)/DoesGPTCheat"
[ -x "$BIN" ] || { echo "build failed: $BIN missing" >&2; exit 1; }
APP="$HERE/build/DoesGPTCheat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DoesGPTCheat"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"
# icon
python3 "$HERE/make_icon.py" >/dev/null
ICONSET="$HERE/build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$HERE/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$HERE/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
case "${1:-}" in
  --run)
    pkill -x DoesGPTCheat 2>/dev/null || true
    open "$APP"
    echo "launched (menu bar)" ;;
  --install)
    DEST="$HOME/Applications/DoesGPTCheat.app"
    mkdir -p "$HOME/Applications"
    pkill -x DoesGPTCheat 2>/dev/null || true
    rm -rf "$DEST" && cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed to $DEST and launched (menu bar); enable 'Launch at login' in the panel's settings" ;;
esac
