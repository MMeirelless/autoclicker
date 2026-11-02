#!/usr/bin/env bash
# Builds the Swift package in release mode and assembles a signed .app bundle in build/.
#
# Signing identity, in order of preference:
#   1. $CODESIGN_IDENTITY (e.g. "Developer ID Application: …" or "Apple Development: …")
#   2. the local certificate created by scripts/make-signing-cert.sh (`make cert`)
#   3. an Apple Development / Developer ID identity found in the default keychains
#   4. ad-hoc ("-"), whose signature changes with every rebuild (Accessibility must be re-granted)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="AutoClicker"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
BIN=".build/release/$APP_NAME"

SIGN_DIR="${AUTOCLICKER_SIGNING_DIR:-$HOME/Library/Application Support/AutoClicker/signing}"
LOCAL_KEYCHAIN="$SIGN_DIR/AutoClicker.keychain-db"
LOCAL_NAME="${SIGNING_NAME:-AutoClicker Local Signing}"
KEYCHAIN_ARGS=()

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  IDENTITY="$CODESIGN_IDENTITY"
elif [ -f "$LOCAL_KEYCHAIN" ] && [ -f "$SIGN_DIR/keychain-password" ]; then
  security unlock-keychain -p "$(cat "$SIGN_DIR/keychain-password")" "$LOCAL_KEYCHAIN"
  IDENTITY="$LOCAL_NAME"
  KEYCHAIN_ARGS=(--keychain "$LOCAL_KEYCHAIN")
else
  APPLE_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Developer ID Application|Apple Development' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
  IDENTITY="${APPLE_IDENTITY:--}"
fi

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

codesign --force --deep ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --sign "$IDENTITY" "$APP"
if [ "$IDENTITY" = "-" ]; then
  echo "Built $APP (ad-hoc signature: run 'make cert' once to stop re-granting Accessibility after rebuilds)"
else
  echo "Built $APP (signed with: $IDENTITY)"
fi
