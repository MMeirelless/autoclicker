#!/usr/bin/env bash
# Builds the Swift package in release mode and assembles a signed .app bundle in build/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="AutoClicker"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
BIN=".build/release/$APP_NAME"
IDENTITY="${CODESIGN_IDENTITY:--}"   # "-" = ad-hoc signature

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# App icon: rendered once by scripts/make-icon.swift, then packed with iconutil.
if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
  rm -rf "$BUILD_DIR/AppIcon.iconset"
  swift scripts/make-icon.swift "$BUILD_DIR/AppIcon.iconset"
  iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
fi
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

sed -e "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"
