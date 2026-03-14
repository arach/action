#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
PACKAGE_DIR="$ROOT_DIR/native/engine"
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
PLIST_TEMPLATE="$PACKAGE_DIR/App/Info.plist"

needs_build=0

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  needs_build=1
elif [[ "$PACKAGE_DIR/Package.swift" -nt "$APP_EXECUTABLE" || "$PLIST_TEMPLATE" -nt "$APP_EXECUTABLE" ]]; then
  needs_build=1
elif find "$PACKAGE_DIR/Sources" -type f -newer "$APP_EXECUTABLE" -print -quit | grep -q .; then
  needs_build=1
fi

if [[ $needs_build -eq 1 ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

exec "$APP_EXECUTABLE" "$@"
