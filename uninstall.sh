#!/bin/sh
# does-gpt-cheat uninstaller. Add --purge to also delete the local ledger (~/.codex/does-gpt-cheat).
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/bin/dgc" teardown "$@"
