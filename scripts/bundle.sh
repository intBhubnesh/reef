#!/bin/bash
# Builds dist/Reef.app (universal, release) and signs it. CODE_SIGN_IDENTITY defaults to ad hoc ("-").
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP="$ROOT/dist/Reef.app"

swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -1
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/reef-app" "$APP/Contents/MacOS/Reef"
cp "$BIN/reef-bridge" "$APP/Contents/Helpers/reef-bridge"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
[ -f "$ROOT/Resources/AppIcon.icns" ] || "$ROOT/scripts/make-icon.sh"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
if [ -d "$ROOT/Resources/BrandIcons" ]; then
  cp -R "$ROOT/Resources/BrandIcons" "$APP/Contents/Resources/"
fi
if [ -d "$ROOT/Resources/Sounds" ]; then
  cp -R "$ROOT/Resources/Sounds" "$APP/Contents/Resources/"
fi
if [ -f "$ROOT/Resources/Fonts/DepartureMono-Regular.otf" ]; then
  mkdir -p "$APP/Contents/Resources/Fonts"
  cp "$ROOT/Resources/Fonts/DepartureMono-Regular.otf" "$APP/Contents/Resources/Fonts/"
fi

codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$ROOT/Resources/Reef.entitlements" \
  --options runtime "$APP/Contents/Helpers/reef-bridge" 2>/dev/null || \
codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP/Contents/Helpers/reef-bridge"
codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$ROOT/Resources/Reef.entitlements" "$APP"
codesign --verify --deep --strict "$APP" && echo "signed with: $CODE_SIGN_IDENTITY"
echo "$APP"
