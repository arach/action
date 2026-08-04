#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
PACKAGE_DIR="$ROOT_DIR/native/engine"
APP_DIR="$ROOT_DIR/native/dist/Action.app"
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
COMMAND="${1:-status}"

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

# Anything the bundle is built from counts: every .swift file under native/engine (Package.swift,
# Sources, CoreSources, AgentSources, AgentCLISources, ProbeSources, and whatever gets added next)
# plus every bundle plist template (App, AgentApp). Scanning by pattern instead of by directory
# means a new source root never needs this check edited again.
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  needs_build=1
elif find "$PACKAGE_DIR" \
  \( -name .build -o -name .git \) -prune -o \
  \( -name '*.swift' -o -name 'Info.plist' \) -type f -newer "$APP_EXECUTABLE" -print -quit \
  | grep -q .; then
  needs_build=1
fi

if [[ $needs_build -eq 1 ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

run_via_open "$@"
