#!/bin/sh
set -eu

LABEL="com.ralfbuilds.ntfy-codex-overlay"
OLD_LABEL="com.ralfbuilds.ntfy-codex-opener"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$HOME/Applications/Ntfy Codex Overlay.app"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
OLD_PLIST="$PLIST_DIR/$OLD_LABEL.plist"
LOG_DIR="$HOME/Library/Logs/ntfy-codex-overlay"
GUI_DOMAIN="gui/$(id -u)"

cd "$SCRIPT_DIR"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PLIST_DIR" "$LOG_DIR"
cp "$BIN_DIR/NtfyCodexOverlay" "$APP_DIR/Contents/MacOS/NtfyCodexOverlay"
cp "$SCRIPT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

if [ "$#" -ge 1 ]; then
  "$APP_DIR/Contents/MacOS/NtfyCodexOverlay" --configure "$1"
fi

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0"><dict>'
  printf '  <key>Label</key><string>%s</string>\n' "$LABEL"
  printf '%s\n' '  <key>ProgramArguments</key><array>'
  printf '    <string>%s</string>\n' "$APP_DIR/Contents/MacOS/NtfyCodexOverlay"
  printf '%s\n' '  </array>'
  printf '%s\n' '  <key>RunAtLoad</key><true/>'
  printf '%s\n' '  <key>KeepAlive</key><true/>'
  printf '%s\n' '  <key>ProcessType</key><string>Interactive</string>'
  printf '  <key>StandardOutPath</key><string>%s/output.log</string>\n' "$LOG_DIR"
  printf '  <key>StandardErrorPath</key><string>%s/error.log</string>\n' "$LOG_DIR"
  printf '%s\n' '</dict></plist>'
} > "$PLIST"

plutil -lint "$APP_DIR/Contents/Info.plist" "$PLIST"

# The native app replaces the original Python listener, avoiding duplicate opens.
launchctl bootout "$GUI_DOMAIN" "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
launchctl bootout "$GUI_DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootstrap "$GUI_DOMAIN" "$PLIST"
launchctl kickstart -k "$GUI_DOMAIN/$LABEL"

echo "Installed and started $APP_DIR"
echo "Toggle the overlay with Control-Shift-0"
if [ "$#" -eq 0 ]; then
  echo "Finish setup in the onboarding window by entering your ntfy topic URL"
fi
