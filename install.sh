#!/bin/sh
# is-gpt-nerfed installer — registers the plugin with Codex (desktop app or CLI), installs the pet, runs doctor.
# Usage: ./install.sh            (set CODEX_BIN=/path/to/codex if codex is not on PATH and not in the ChatGPT app)
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$ROOT/plugin/skills/is-gpt-nerfed/scripts/nerfed" "$ROOT/bin/nerfed" 2>/dev/null || true
if [ -n "${CODEX_BIN:-}" ]; then
  "$ROOT/bin/nerfed" config init >/dev/null
  "$ROOT/bin/nerfed" config set codex_bin "$CODEX_BIN"
fi
exec "$ROOT/bin/nerfed" setup "$@"
