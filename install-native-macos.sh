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

# `open` does not launch a second copy when Codex Notch is already running.
# Stop the old executable after a successful build so the newly installed
# binary—and its listener—actually takes effect.
pkill -x CodexNotch 2>/dev/null || true
for _ in 1 2 3 4 5; do
  pgrep -x CodexNotch >/dev/null 2>&1 || break
  sleep 0.1
done

launchctl bootout "$GUI_DOMAIN" "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
rm -rf "$OLD_APP_DIR"
open "$APP_DIR"

echo "Installed and opened $APP_DIR"
echo "Finish local hook setup in the Codex Notch window."
