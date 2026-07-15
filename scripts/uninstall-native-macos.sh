#!/bin/sh
set -eu

APP_DIR="$HOME/Applications/Codex Notch.app"
OLD_APP_DIR="$HOME/Applications/Ntfy Codex Overlay.app"
OLD_PLIST="$HOME/Library/LaunchAgents/com.ralfbuilds.ntfy-codex-overlay.plist"
OLDER_PLIST="$HOME/Library/LaunchAgents/com.ralfbuilds.ntfy-codex-opener.plist"

if [ -x "$APP_DIR/Contents/MacOS/CodexNotch" ]; then
  pkill -TERM -x CodexNotch 2>/dev/null || true
  attempts=0
  while pgrep -x CodexNotch >/dev/null 2>&1 && [ "$attempts" -lt 50 ]; do
    sleep 0.1
    attempts=$((attempts + 1))
  done
  "$APP_DIR/Contents/MacOS/CodexNotch" --prepare-uninstall
fi
launchctl bootout "gui/$(id -u)" "$OLD_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$OLDER_PLIST" 2>/dev/null || true
/usr/bin/defaults delete com.ralfbuilds.CodexNotch >/dev/null 2>&1 || true
/usr/bin/defaults delete com.ralfbuilds.NtfyCodexOverlay >/dev/null 2>&1 || true
rm -f "$OLD_PLIST" "$OLDER_PLIST"
rm -rf \
  "$APP_DIR" \
  "$OLD_APP_DIR" \
  "$HOME/Library/Application Support/Codex Notch" \
  "$HOME/Library/Application Support/Ntfy Codex Overlay" \
  "$HOME/Library/Application Support/com.ralfbuilds.CodexNotch" \
  "$HOME/Library/Application Support/com.ralfbuilds.NtfyCodexOverlay" \
  "$HOME/Library/Caches/com.ralfbuilds.CodexNotch" \
  "$HOME/Library/Caches/com.ralfbuilds.NtfyCodexOverlay" \
  "$HOME/Library/Preferences/com.ralfbuilds.CodexNotch.plist" \
  "$HOME/Library/Preferences/com.ralfbuilds.NtfyCodexOverlay.plist" \
  "$HOME/Library/Saved Application State/com.ralfbuilds.CodexNotch.savedState" \
  "$HOME/Library/Saved Application State/com.ralfbuilds.NtfyCodexOverlay.savedState" \
  "$HOME/Library/HTTPStorages/com.ralfbuilds.CodexNotch" \
  "$HOME/Library/HTTPStorages/com.ralfbuilds.NtfyCodexOverlay" \
  "$HOME/Library/WebKit/com.ralfbuilds.CodexNotch" \
  "$HOME/Library/WebKit/com.ralfbuilds.NtfyCodexOverlay" \
  "$HOME/Library/Logs/ntfy-codex-overlay"
echo "Removed Codex Notch from the Mac and all paired remote hosts."
