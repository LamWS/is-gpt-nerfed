#!/bin/sh
# Install or update IsGPTNerfed.app from the latest GitHub release, then open it.
#   curl -fsSL https://raw.githubusercontent.com/kiyoakii/is-gpt-nerfed/main/install-app.sh | sh
# curl does not set the quarantine flag, so an app installed this way opens without the Gatekeeper block that a
# browser download of a non-notarized app gets. The archive's sha256 (published next to it) is checked first.
set -eu
REPO="kiyoakii/is-gpt-nerfed"
JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest")" \
  || { echo "cannot read the latest release of $REPO (offline, or the repository is not public yet)" >&2; exit 1; }
pick() { printf '%s' "$JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin); key = sys.argv[1]
if key == "tag": print(d.get("tag_name") or ""); sys.exit()
a = sorted((x for x in d.get("assets", []) if str(x.get("name", "")).lower().endswith(key)),
           key=lambda x: (not str(x.get("name", "")).startswith("IsGPTNerfed"), str(x.get("name", ""))))
print(a[0]["browser_download_url"] if a else "")' "$1"; }
TAG="$(pick tag)"; ZIP_URL="$(pick .zip)"; SUM_URL="$(pick .sha256)"
[ -n "$ZIP_URL" ] || { echo "release $TAG has no zip attached" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "downloading IsGPTNerfed $TAG …"
curl -fsSL -o "$TMP/app.zip" "$ZIP_URL"
if [ -n "$SUM_URL" ]; then
  EXPECTED="$(curl -fsSL "$SUM_URL" | awk '{print $1}')"
  ACTUAL="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [ "$EXPECTED" = "$ACTUAL" ] || { echo "checksum mismatch: the archive is not the one the release lists" >&2; exit 1; }
fi
ditto -x -k "$TMP/app.zip" "$TMP/x"
APP="$(find "$TMP/x" -maxdepth 2 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "no .app inside the archive" >&2; exit 1; }
DEST_DIR="/Applications"; [ -w "$DEST_DIR" ] || DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/IsGPTNerfed.app"
pkill -x IsGPTNerfed 2>/dev/null || true
rm -rf "$DEST"; ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"
echo "installed $TAG to $DEST. Click the face in the menu bar and press Install (once) to register the plugin with Codex."
