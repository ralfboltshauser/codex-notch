#!/bin/sh
set -eu

LABEL="com.ralfbuilds.ntfy-codex-overlay"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Applications/Ntfy Codex Overlay.app"
GUI_DOMAIN="gui/$(id -u)"

launchctl bootout "$GUI_DOMAIN" "$PLIST" 2>/dev/null || true
if [ -x "$APP_DIR/Contents/MacOS/NtfyCodexOverlay" ]; then
  "$APP_DIR/Contents/MacOS/NtfyCodexOverlay" --uninstall-hook
fi
rm -f "$PLIST"
rm -rf "$APP_DIR"
echo "Stopped Ntfy Codex Overlay and removed its Codex hook"
