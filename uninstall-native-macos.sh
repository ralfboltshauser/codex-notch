#!/bin/sh
set -eu

APP_DIR="$HOME/Applications/Codex Notch.app"
OLD_APP_DIR="$HOME/Applications/Ntfy Codex Overlay.app"
OLD_PLIST="$HOME/Library/LaunchAgents/com.ralfbuilds.ntfy-codex-overlay.plist"

if [ -x "$APP_DIR/Contents/MacOS/CodexNotch" ]; then
  "$APP_DIR/Contents/MacOS/CodexNotch" --uninstall-hook || true
fi
launchctl bootout "gui/$(id -u)" "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
rm -rf "$APP_DIR" "$OLD_APP_DIR"
echo "Removed Codex Notch and its local Codex hook."
