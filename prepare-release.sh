#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 VERSION" >&2
  exit 2
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This release preparation script must run on macOS" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLIST="$SCRIPT_DIR/AppResources/Info.plist"
VERSION=$1

printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "Version must use MAJOR.MINOR.PATCH format" >&2
  exit 2
}

BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
BUILD=$((BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
plutil -lint "$PLIST"
python3 "$SCRIPT_DIR/changelog.py" validate

echo "Prepared Codex Notch $VERSION (build $BUILD)."
echo "Commit this change, then push tag v$VERSION to publish the signed update."
