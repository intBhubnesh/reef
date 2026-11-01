#!/bin/bash
# Produces a universal Reef.app, a drag-to-Applications DMG, and a SHA-256 checksum.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
APP="$ROOT/dist/Reef.app"
DMG="$ROOT/dist/Reef-$VERSION-universal.dmg"
CHECKSUM="$DMG.sha256"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/reef-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

"$ROOT/scripts/bundle.sh"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Reef")"
case " $ARCHS " in
  *" arm64 "*) ;;
  *) echo "release error: Reef is missing arm64" >&2; exit 1 ;;
esac
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) echo "release error: Reef is missing x86_64" >&2; exit 1 ;;
esac

codesign --verify --deep --strict "$APP"
mkdir -p "$STAGING/Reef $VERSION"
ditto "$APP" "$STAGING/Reef $VERSION/Reef.app"
ln -s /Applications "$STAGING/Reef $VERSION/Applications"
cp "$ROOT/README.md" "$STAGING/Reef $VERSION/README.md"
cp "$ROOT/CHANGELOG.md" "$STAGING/Reef $VERSION/CHANGELOG.md"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGING/Reef $VERSION/THIRD_PARTY_NOTICES.md"

rm -f "$DMG" "$CHECKSUM"
hdiutil create \
  -volname "Reef $VERSION" \
  -srcfolder "$STAGING/Reef $VERSION" \
  -format UDZO \
  -ov \
  "$DMG"

if [[ "${CODE_SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG"
fi

(
  cd "$ROOT/dist"
  shasum -a 256 "$(basename "$DMG")" > "$(basename "$CHECKSUM")"
)

echo "Reef $VERSION ($BUILD)"
echo "Architectures: $ARCHS"
echo "$APP"
echo "$DMG"
echo "$CHECKSUM"
