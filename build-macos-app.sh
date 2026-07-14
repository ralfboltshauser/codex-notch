#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This build script must run on macOS" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=${1:-"$SCRIPT_DIR/.build/dist/Codex Notch.app"}
IDENTITY=${CODE_SIGN_IDENTITY:--}

cd "$SCRIPT_DIR"
swift build -c release --product CodexNotch
swift build -c release --product CodexNotchHook
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Helpers" \
  "$APP_DIR/Contents/Resources/remote"
install -m 0755 "$BIN_DIR/CodexNotch" "$APP_DIR/Contents/MacOS/CodexNotch"
install -m 0755 "$BIN_DIR/CodexNotchHook" "$APP_DIR/Contents/Helpers/CodexNotchHook"
install -m 0755 "$SCRIPT_DIR/remote/codex_notch_remote.py" \
  "$APP_DIR/Contents/Resources/remote/codex_notch_remote.py"
install -m 0644 "$SCRIPT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP_DIR/Contents/Helpers/CodexNotchHook"
  codesign --force --sign - "$APP_DIR/Contents/MacOS/CodexNotch"
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Helpers/CodexNotchHook"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/MacOS/CodexNotch"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_DIR"
fi
codesign --verify --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
