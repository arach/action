#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
PACKAGE_DIR="$ROOT_DIR/native/engine"
APP_TEMPLATE_DIR="$PACKAGE_DIR/App"
DIST_DIR="$ROOT_DIR/native/dist"
APP_DIR="$DIST_DIR/Action.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_TEMPLATE="$APP_TEMPLATE_DIR/Info.plist"
LOCK_DIR="$ROOT_DIR/native/.action-build.lock"

detect_identity() {
  if [[ -n "${ACTION_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$ACTION_CODESIGN_IDENTITY"
    return
  fi

  local identity

  identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi

  identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:/{print $2; exit}')
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi

  printf '%s\n' "-"
}

acquire_lock() {
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    sleep 0.1
  done
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock
trap release_lock EXIT

swift build --package-path "$PACKAGE_DIR" -c debug >&2

BIN_DIR=$(swift build --package-path "$PACKAGE_DIR" -c debug --show-bin-path)
HOST_EXECUTABLE="$BIN_DIR/ActionHost"
APP_EXECUTABLE="$MACOS_DIR/Action"
SIGNING_IDENTITY=$(detect_identity)

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$HOST_EXECUTABLE" "$APP_EXECUTABLE"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"

codesign --force --sign "$SIGNING_IDENTITY" "$APP_EXECUTABLE" >&2
codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR" >&2

printf 'codesigned-with=%s\n' "$SIGNING_IDENTITY" >&2

"$SCRIPT_DIR/verify-app.sh" >&2

printf '%s\n' "$APP_DIR"
