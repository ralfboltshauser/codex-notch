#!/bin/sh
set -eu

INSTALL_DIR="$HOME/.local/lib/codex-notch"
HOOK="$INSTALL_DIR/codex_notch_remote-v1.py"
LIVE="$INSTALL_DIR/codex_notch_live-v1.py"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CLEANER="$REPO_ROOT/apps/linux/codex_notch_remote.py"

if [ -x "$HOOK" ]; then
  "$HOOK" --uninstall
elif [ -f "$CLEANER" ]; then
  python3 "$CLEANER" --uninstall
else
  echo "The Codex Notch cleanup program is missing." >&2
  exit 1
fi
rm -f "$HOOK"
rm -f "$LIVE"
rmdir "$INSTALL_DIR" 2>/dev/null || true
echo "Removed the Ubuntu publishers, hook and hook backup, services, configuration, and queue."
