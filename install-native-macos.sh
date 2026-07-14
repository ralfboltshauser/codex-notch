#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer must run on macOS" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$HOME/Applications/Codex Notch.app"
OLD_APP_DIR="$HOME/Applications/Ntfy Codex Overlay.app"
OLD_PLIST="$HOME/Library/LaunchAgents/com.ralfbuilds.ntfy-codex-overlay.plist"
GUI_DOMAIN="gui/$(id -u)"
"$SCRIPT_DIR/build-macos-app.sh" "$APP_DIR"

launchctl bootout "$GUI_DOMAIN" "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
rm -rf "$OLD_APP_DIR"
open "$APP_DIR"

echo "Installed and opened $APP_DIR"
echo "Finish local hook setup in the Codex Notch window."
