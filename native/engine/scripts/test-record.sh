#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUTPUT="${2:-/tmp/action-record-$(date +%Y%m%d-%H%M%S).mov}"
STOP_FILE="${OUTPUT}.stop"
LOG_FILE="${OUTPUT}.log"
STOP_DELAY="${ACTION_RECORD_SECONDS:-5}"
X="${ACTION_CAPTURE_X:-320}"
Y="${ACTION_CAPTURE_Y:-180}"
WIDTH="${ACTION_CAPTURE_WIDTH:-960}"
HEIGHT="${ACTION_CAPTURE_HEIGHT:-720}"

rm -f "$STOP_FILE"
rm -f "$LOG_FILE"

(
  sleep "$STOP_DELAY"
  printf 'stop\n' > "$STOP_FILE"
) &

"$SCRIPT_DIR/run-app-host.sh" record-region --x "$X" --y "$Y" --width "$WIDTH" --height "$HEIGHT" --fps "${ACTION_RECORD_FPS:-15}" --scale "${ACTION_RECORD_SCALE:-0.75}" --output "$OUTPUT" --stop-file "$STOP_FILE" --debug-log "$LOG_FILE"

rm -f "$STOP_FILE"
ls -lh "$OUTPUT"
echo "debug-log=$LOG_FILE"
