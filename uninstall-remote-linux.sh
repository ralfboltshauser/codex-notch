#!/bin/sh
set -eu

INSTALL_DIR="$HOME/.local/lib/codex-notch"
HOOK="$INSTALL_DIR/codex_notch_remote-v1.py"

if [ -x "$HOOK" ]; then
  "$HOOK" --uninstall
  rm -f "$HOOK"
  rmdir "$INSTALL_DIR" 2>/dev/null || true
  echo "Removed the Ubuntu publisher and its Codex Stop hook."
else
  echo "Codex Notch Ubuntu publisher is not installed."
fi
