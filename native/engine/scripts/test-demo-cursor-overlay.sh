#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
CONTROL_FILE="${ACTION_TERMINAL_CONTROL_FILE:-/tmp/action-overlay-smoke.controls}"
STOP_FILE="${ACTION_TERMINAL_STOP_FILE:-/tmp/action-overlay-smoke.stop}"
OUTPUT_PREFIX="${1:-/tmp/action-overlay-smoke-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_PREFIX="${OUTPUT_PREFIX%.png}"

rm -f "$CONTROL_FILE" "$STOP_FILE"

"$SCRIPT_DIR/run-app-host.sh" terminal-session \
  --control-file "$CONTROL_FILE" \
  --stop-file "$STOP_FILE" \
  --cwd "$ROOT_DIR"

sleep 0.9

"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 900 \
  --start-x 3060 \
  --start-y 910 \
  --end-x 2410 \
  --end-y 995 \
  --click-progress 0.72 \
  --label Click

sleep 0.35
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-click.png"
sleep 1.0

"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 2600 \
  --start-x 2410 \
  --start-y 995 \
  --end-x 2410 \
  --end-y 995 \
  --click-progress 0.50 \
  --label Typing \
  --typing-text 'echo "overlay smoke typing"'

sleep 0.25
printf 'echo "overlay smoke typing"\n' >> "$CONTROL_FILE"
sleep 0.55
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-typing.png"
sleep 2.2

"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 900 \
  --start-x 2410 \
  --start-y 995 \
  --end-x 3070 \
  --end-y 920 \
  --click-progress 0.95 \
  --label Move

sleep 0.35
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-move.png"
sleep 1.0

"$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
  --duration-ms 1100 \
  --start-x 3070 \
  --start-y 920 \
  --end-x 3070 \
  --end-y 920 \
  --click-progress 0.50 \
  --label Command-Tab \
  --key-label Command-Tab

sleep 0.5
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen \
  --output "$OUTPUT_PREFIX-key.png"

printf 'stop\n' > "$STOP_FILE"
ls -lh "$OUTPUT_PREFIX"-*.png
