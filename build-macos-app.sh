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
  "$APP_DIR/Contents/Frameworks" \
  "$APP_DIR/Contents/Resources/ThirdPartyNotices" \
  "$APP_DIR/Contents/Resources/remote"
install -m 0755 "$BIN_DIR/CodexNotch" "$APP_DIR/Contents/MacOS/CodexNotch"
install -m 0755 "$BIN_DIR/CodexNotchHook" "$APP_DIR/Contents/Helpers/CodexNotchHook"
install -m 0755 "$SCRIPT_DIR/remote/codex_notch_remote.py" \
  "$APP_DIR/Contents/Resources/remote/codex_notch_remote.py"
install -m 0644 "$SCRIPT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

SPARKLE_FRAMEWORK=$(find "$SCRIPT_DIR/.build/artifacts" -type d \
  -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' \
  -print -quit)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "Sparkle.framework was not found in SwiftPM artifacts" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
SPARKLE_LICENSE=$(find "$SCRIPT_DIR/.build/artifacts" -type f -name LICENSE -print -quit)
if [ -n "$SPARKLE_LICENSE" ]; then
  install -m 0644 "$SPARKLE_LICENSE" \
    "$APP_DIR/Contents/Resources/ThirdPartyNotices/Sparkle-LICENSE"
fi
plutil -lint "$APP_DIR/Contents/Info.plist"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign - --preserve-metadata=entitlements \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign - \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  codesign --force --sign - \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  codesign --force --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign - "$APP_DIR/Contents/Helpers/CodexNotchHook"
  codesign --force --sign - "$APP_DIR/Contents/MacOS/CodexNotch"
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  codesign --force --timestamp --options runtime --preserve-metadata=entitlements \
    --sign "$IDENTITY" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/Helpers/CodexNotchHook"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP_DIR/Contents/MacOS/CodexNotch"
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
