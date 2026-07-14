#!/bin/sh
set -eu

: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"

if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
  echo "A Developer ID Application identity is required for distribution" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DIST_DIR="$SCRIPT_DIR/.build/dist"
APP="$DIST_DIR/Codex Notch.app"
ARCHIVE="$DIST_DIR/CodexNotch.zip"

mkdir -p "$DIST_DIR"
"$SCRIPT_DIR/build-macos-app.sh" "$APP"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
spctl --assess --type execute --verbose=2 "$APP"
echo "$ARCHIVE"
