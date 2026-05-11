#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
PACKAGE_DIR="$ROOT_DIR/native/engine"
APP_DIR="$ROOT_DIR/native/dist/Action.app"
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
PLIST_TEMPLATE="$PACKAGE_DIR/App/Info.plist"
COMMAND="${1:-status}"
NORMALIZED_HOST_ARGS=()

is_path_value_flag() {
  case "$1" in
    --control-file|--debug-log|--file-path|--finished-file|--output|--reply-file|--state-file|--stop-file|--trace-file)
      return 0
      ;;
  esac

  return 1
}

absolute_host_path() {
  local value="$1"
  if [[ "$value" == /* ]]; then
    print -r -- "$value"
    return
  fi

  print -r -- "$ROOT_DIR/$value"
}

normalize_host_args() {
  local expect_path=0
  local arg
  NORMALIZED_HOST_ARGS=()

  for arg in "$@"; do
    if [[ "$expect_path" -eq 1 ]]; then
      NORMALIZED_HOST_ARGS+=("$(absolute_host_path "$arg")")
      expect_path=0
      continue
    fi

    NORMALIZED_HOST_ARGS+=("$arg")
    if is_path_value_flag "$arg"; then
      expect_path=1
    fi
  done
}

run_direct() {
  exec "$APP_EXECUTABLE" "$@"
}

run_via_open() {
  local reply_file
  local attempt
  reply_file=$(mktemp "${TMPDIR:-/tmp}/action-host.XXXXXX")

  open -n "$APP_DIR" --args "$@" --reply-file "$reply_file" >/dev/null

  for attempt in {1..100}; do
    if [[ -s "$reply_file" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ -s "$reply_file" ]]; then
    cat "$reply_file"
    if grep -q '"status"[[:space:]]*:[[:space:]]*"error"' "$reply_file"; then
      rm -f "$reply_file"
      return 1
    fi
    rm -f "$reply_file"
    return 0
  fi

  rm -f "$reply_file"
  echo "ActionHost did not write a reply file for command $*" >&2
  return 1
}

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

normalize_host_args "$@"
run_via_open "${NORMALIZED_HOST_ARGS[@]}"
