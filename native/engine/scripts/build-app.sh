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

swift build --package-path "$PACKAGE_DIR" -c debug >&2

BIN_DIR=$(swift build --package-path "$PACKAGE_DIR" -c debug --show-bin-path)
HOST_EXECUTABLE="$BIN_DIR/ActionHost"
APP_EXECUTABLE="$MACOS_DIR/Action"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$HOST_EXECUTABLE" "$APP_EXECUTABLE"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

printf '%s\n' "$APP_DIR"
