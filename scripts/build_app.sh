#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Voice2Input"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
DEFAULT_SIGN_IDENTITY="${VOICE2INPUT_SIGN_IDENTITY:-Voice2Input Local Signing}"

resolve_sign_identity() {
  if security find-identity -v -p codesigning | grep -Fq "$DEFAULT_SIGN_IDENTITY"; then
    printf '%s' "$DEFAULT_SIGN_IDENTITY"
    return
  fi

  printf '%s' "-"
}

swift build \
  --package-path "$ROOT_DIR" \
  -c "$CONFIGURATION" \
  --product "$APP_NAME"

if [[ "$CONFIGURATION" == "release" ]]; then
  BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
else
  BINARY_PATH="$ROOT_DIR/.build/debug/$APP_NAME"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
SIGN_IDENTITY="$(resolve_sign_identity)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
echo "Signed with $SIGN_IDENTITY"
