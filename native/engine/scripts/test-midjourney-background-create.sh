#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
BUN_BIN="${BUN_BIN:-$HOME/.bun/bin/bun}"
TRACE_FILE="${ACTION_MIDJOURNEY_TRACE_FILE:-/tmp/action-midjourney-bg-create.trace}"
OUTPUT_DIR="${ACTION_MIDJOURNEY_OUTPUT_DIR:-/tmp/action-midjourney-bg-create-$(date +%Y%m%d-%H%M%S)}"
CHROME_BUNDLE_ID="${ACTION_CHROME_BG_BUNDLE_ID:-com.google.Chrome}"
TARGET_URL="${ACTION_MIDJOURNEY_URL:-https://www.midjourney.com/imagine}"
PROMPT="${ACTION_MIDJOURNEY_PROMPT:-a polished product demo frame of a tiny translucent cursor arranging warm cream mechanical keyboard switches on a moonlit desk, cinematic macro lighting, soft editorial composition}"
MOONDREAM_PYTHON="${ACTION_MOONDREAM_PYTHON:-/Users/art/dev/moondream-local-poc/.venv/bin/python}"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

if [[ ! -x "$BUN_BIN" ]]; then
  echo "bun was not found at $BUN_BIN" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$TRACE_FILE"

front_bundle() {
  local asn
  asn=$(lsappinfo front 2>/dev/null | awk '{print $1}' | sed 's/ASN://;s/:$//' || true)
  [[ -n "$asn" ]] || return 0
  lsappinfo info -only bundleid "ASN:$asn" 2>/dev/null \
    | sed -n 's/^"CFBundleIdentifier"="\(.*\)"$/\1/p' \
    | head -1
}

log_event() {
  local kind="$1"
  local text="$2"
  printf '%s|%s\n' "$kind" "$text" >> "$TRACE_FILE"
  printf '[%s] %s\n' "$kind" "$text"
}

overlay() {
  local label="$1"
  local duration_ms="$2"
  local detail="$3"
  shift 3
  "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
    --duration-ms "$duration_ms" \
    --status-only true \
    --label "$label" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Midjourney background create" \
    "$@" >/dev/null 2>&1 &
}

start_action_overlay() {
  local label="$1"
  local duration_ms="$2"
  local detail="$3"
  shift 3
  if [[ "$TARGET_IS_FRONTMOST" == "true" ]]; then
    "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
      --duration-ms "$duration_ms" \
      --label "$label" \
      --status-detail "$detail" \
      --trace-file "$TRACE_FILE" \
      --trace-title "Midjourney background create" \
      "$@" >/dev/null 2>&1 &
  else
    "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay \
      --duration-ms "$duration_ms" \
      --status-only true \
      --label "$label" \
      --status-detail "background Chrome: $detail" \
      --trace-file "$TRACE_FILE" \
      --trace-title "Midjourney background create" >/dev/null 2>&1 &
  fi
  printf '%s\n' "$!"
}

snapshot_chrome() {
  local name="$1"
  local path="$OUTPUT_DIR/$name.json"
  "$APP_EXECUTABLE" inspect-app-ui \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --max-depth 18 \
    --max-nodes 6000 > "$path"
  printf '%s\n' "$path"
}

summarize_snapshot() {
  local path="$1"
  "$BUN_BIN" - "$path" <<'BUN'
const fs = require("fs");
const nodes = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const window = nodes.find((node) => node.role === "AXWindow");
const urlField = nodes.find((node) => node.role === "AXTextField" && /address and search bar/i.test(text(node)));
const textArea = nodes.find((node) => node.role === "AXTextArea");
const images = nodes.filter((node) => /cdn\.midjourney\.com/i.test(text(node)) && node.frame && node.frame.height > 10);
console.log(JSON.stringify({
  nodes: nodes.length,
  windowTitle: window?.title ?? null,
  url: urlField?.value ?? null,
  textAreaFocused: textArea?.focused ?? null,
  textAreaValue: textArea?.value ?? null,
  imageRefs: images.length,
}));
BUN
}

resolve_text_area_point() {
  local tree_json="$1"
  local screen_png="$2"
  local point_json="$3"
  "$BUN_BIN" - "$tree_json" "$screen_png" "$point_json" <<'BUN'
const fs = require("fs");
const { execFileSync } = require("child_process");
const [treePath, screenPath, pointPath] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(treePath, "utf8"));
const area = nodes.find((node) => node.role === "AXTextArea" && node.frame);
if (!area) {
  throw new Error("Could not resolve Midjourney prompt AXTextArea");
}

const sips = execFileSync("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", screenPath], { encoding: "utf8" });
const widthMatch = sips.match(/pixelWidth:\s*(\d+)/);
const heightMatch = sips.match(/pixelHeight:\s*(\d+)/);
const screenWidth = widthMatch ? Number(widthMatch[1]) : 3024;
const screenHeight = heightMatch ? Number(heightMatch[1]) : 1964;
const x = Math.round(area.frame.x + Math.min(260, area.frame.width * 0.34));
const y = Math.round(screenHeight - (area.frame.y + area.frame.height / 2));
const startX = Math.max(42, Math.min(screenWidth - 80, x + 420));
const startY = Math.max(86, Math.min(screenHeight - 90, y + 220));
fs.writeFileSync(pointPath, JSON.stringify({
  area,
  overlayPoint: { x, y },
  startPoint: { x: startX, y: startY },
  screen: { width: screenWidth, height: screenHeight },
}, null, 2));
BUN
}

extract_image_refs() {
  local path="$1"
  "$BUN_BIN" - "$path" <<'BUN'
const fs = require("fs");
const nodes = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const text = (node) => [node.title, node.detail, node.value, node.identifier].filter(Boolean).join(" | ");
const refs = nodes
  .filter((node) => /cdn\.midjourney\.com/i.test(text(node)) && node.frame && node.frame.height > 10)
  .map((node) => text(node).match(/https:\/\/cdn\.midjourney\.com\/[^\s|"]+/i)?.[0])
  .filter(Boolean);
console.log([...new Set(refs)].sort().join("\n"));
BUN
}

page_contains_prompt() {
  local path="$1"
  local prompt="$2"
  "$BUN_BIN" - "$path" "$prompt" <<'BUN'
const fs = require("fs");
const [path, prompt] = process.argv.slice(2);
const nodes = JSON.parse(fs.readFileSync(path, "utf8"));
const normalize = (value) => String(value || "").toLowerCase().replace(/\s+/g, " ").trim();
const needle = normalize(prompt).slice(0, 74);
const haystack = normalize(nodes.map((node) => [node.title, node.detail, node.value].filter(Boolean).join(" ")).join(" "));
const hasPrompt = needle.length > 20 && haystack.includes(needle);
const hasRenderedCards = nodes.some((node) => {
  const text = [node.title, node.detail, node.value].filter(Boolean).join(" ");
  return /cdn\.midjourney\.com/i.test(text) && node.frame && node.frame.width > 40 && node.frame.height > 10;
});
process.exit(hasPrompt && hasRenderedCards ? 0 : 1);
BUN
}

verify_with_moondream() {
  local image_path="$1"
  local output_path="$2"
  if [[ "${ACTION_MOONDREAM_VERIFY:-1}" == "0" ]]; then
    printf '{"available":false,"skipped":true}\n' > "$output_path"
    return 1
  fi
  if [[ ! -x "$MOONDREAM_PYTHON" ]]; then
    printf '{"available":false,"error":"Moondream Python runtime not found"}\n' > "$output_path"
    return 1
  fi
  "$MOONDREAM_PYTHON" "$SCRIPT_DIR/moondream-verify-screenshot.py" "$image_path" "$PROMPT" > "$output_path"
}

navigate_background() {
  log_event "act" "navigate Chrome to Midjourney Create without activation"
  "$APP_EXECUTABLE" set-accessibility-value \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --role AXTextField \
    --label "Address and search bar" \
    --value "$TARGET_URL" >/dev/null
  "$APP_EXECUTABLE" perform-accessibility-action \
    --bundle-id "$CHROME_BUNDLE_ID" \
    --role AXTextField \
    --label "Address and search bar" \
    --action AXPress >/dev/null
  "$APP_EXECUTABLE" press-app-key --bundle-id "$CHROME_BUNDLE_ID" --key return >/dev/null
}

if ! pgrep -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" >/dev/null 2>&1; then
  log_event "abort" "Google Chrome is not running; refusing to launch it during background test"
  overlay "Chrome not running" 2200 "open Chrome first"
  wait || true
  exit 1
fi

FRONT_BEFORE=$(front_bundle)
TARGET_IS_FRONTMOST=false
if [[ "${FRONT_BEFORE:-}" == "$CHROME_BUNDLE_ID" ]]; then
  TARGET_IS_FRONTMOST=true
fi
log_event "observe" "frontmost before: ${FRONT_BEFORE:-unknown}"
log_event "policy" "submitting the prompt may consume Midjourney generation credits"
log_event "policy" "decorative cursor disabled for background targets"
overlay "Observe" 1200 "scan Create page"

BEFORE_JSON=$(snapshot_chrome "01-before")
log_event "resolve" "before: $(summarize_snapshot "$BEFORE_JSON")"
if ! grep -qi "midjourney.com" "$BEFORE_JSON" || ! grep -qi "AXTextArea" "$BEFORE_JSON"; then
  navigate_background
  sleep 3
  BEFORE_JSON=$(snapshot_chrome "01-before-navigated")
  log_event "resolve" "after navigation: $(summarize_snapshot "$BEFORE_JSON")"
fi

BEFORE_REFS="$OUTPUT_DIR/before-refs.txt"
extract_image_refs "$BEFORE_JSON" > "$BEFORE_REFS"

SCREEN_PROBE="$OUTPUT_DIR/screen.png"
POINT_JSON="$OUTPUT_DIR/prompt-point.json"
"$SCRIPT_DIR/run-app-host.sh" screenshot-screen --output "$SCREEN_PROBE" >/dev/null
resolve_text_area_point "$BEFORE_JSON" "$SCREEN_PROBE" "$POINT_JSON"

PROMPT_X=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').overlayPoint.x)")
PROMPT_Y=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').overlayPoint.y)")
START_X=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').startPoint.x)")
START_Y=$("$BUN_BIN" -e "console.log(require('$POINT_JSON').startPoint.y)")

log_event "resolve" "resolved prompt field at $PROMPT_X,$PROMPT_Y"
log_event "act" "visual click/focus prompt field"
CLICK_PID=$(start_action_overlay \
  "Click" \
  950 \
  "focus prompt via AX" \
  --start-x "$START_X" \
  --start-y "$START_Y" \
  --end-x "$PROMPT_X" \
  --end-y "$PROMPT_Y" \
  --click-progress 0.62)
sleep 0.52
"$APP_EXECUTABLE" set-accessibility-role-value \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --role AXTextArea \
  --value " " >/dev/null
wait "$CLICK_PID" || true

log_event "act" "visual typing prompt"
TYPE_DURATION_MS=$(( 1600 + ${#PROMPT} * 34 ))
TYPE_PID=$(start_action_overlay \
  "Typing" \
  "$TYPE_DURATION_MS" \
  "prompt into background AXTextArea" \
  --start-x "$PROMPT_X" \
  --start-y "$PROMPT_Y" \
  --end-x "$PROMPT_X" \
  --end-y "$PROMPT_Y" \
  --click-progress 0.50 \
  --typing-text "$PROMPT" \
  --typing-sound timed)
sleep 0.20
"$APP_EXECUTABLE" press-app-key --bundle-id "$CHROME_BUNDLE_ID" --key a --modifiers cmd >/dev/null
"$APP_EXECUTABLE" type-app-text --bundle-id "$CHROME_BUNDLE_ID" --text "$PROMPT" --delay-ms 4 >/dev/null
wait "$TYPE_PID" || true

AFTER_TYPE_JSON=$(snapshot_chrome "02-after-type")
log_event "observe" "after typing: $(summarize_snapshot "$AFTER_TYPE_JSON")"

log_event "act" "submit prompt with process-directed Return"
RETURN_PID=$(start_action_overlay \
  "Return" \
  900 \
  "submit prompt" \
  --start-x "$PROMPT_X" \
  --start-y "$PROMPT_Y" \
  --end-x "$PROMPT_X" \
  --end-y "$PROMPT_Y" \
  --click-progress 0.50 \
  --key-label "Return")
sleep 0.35
"$APP_EXECUTABLE" press-app-key --bundle-id "$CHROME_BUNDLE_ID" --key return >/dev/null
wait "$RETURN_PID" || true

RESULT_JSON=""
RESULT_REFS="$OUTPUT_DIR/result-refs.txt"
NEW_REF=""
for attempt in {1..24}; do
  sleep 6
  CANDIDATE_JSON=$(snapshot_chrome "03-poll-$attempt")
  extract_image_refs "$CANDIDATE_JSON" > "$RESULT_REFS"
  NEW_REF=$(comm -13 "$BEFORE_REFS" "$RESULT_REFS" | head -1 || true)
  log_event "observe" "poll $attempt: $(summarize_snapshot "$CANDIDATE_JSON")"
  if [[ -n "$NEW_REF" ]] || page_contains_prompt "$CANDIDATE_JSON" "$PROMPT"; then
    RESULT_JSON="$CANDIDATE_JSON"
    break
  fi
done

PREVIEW_IMAGE="$OUTPUT_DIR/midjourney-window.png"
"$SCRIPT_DIR/run-app-host.sh" screenshot-app-window \
  --bundle-id "$CHROME_BUNDLE_ID" \
  --output "$PREVIEW_IMAGE" >/dev/null

MOONDREAM_JSON="$OUTPUT_DIR/moondream.json"
MOONDREAM_RENDERED=false
if verify_with_moondream "$PREVIEW_IMAGE" "$MOONDREAM_JSON"; then
  MOONDREAM_RENDERED=true
  log_event "verify" "Moondream sees rendered result"
else
  log_event "verify" "Moondream did not confirm rendered result"
fi

if [[ -n "$NEW_REF" ]]; then
  log_event "done" "new image detected: $NEW_REF"
  overlay "Rendered" 5500 "new image detected" --preview-image "$PREVIEW_IMAGE"
elif [[ "$MOONDREAM_RENDERED" == "true" ]]; then
  log_event "done" "screen capture verified by Moondream"
  overlay "Rendered" 5500 "Moondream verified screenshot" --preview-image "$PREVIEW_IMAGE"
elif [[ -n "$RESULT_JSON" ]]; then
  log_event "done" "rendered prompt detected in Create page"
  overlay "Rendered" 5500 "prompt visible with image cards" --preview-image "$PREVIEW_IMAGE"
else
  log_event "warn" "no new image detected before timeout"
  overlay "Preview" 5500 "captured current Create page" --preview-image "$PREVIEW_IMAGE"
fi

wait || true
FRONT_AFTER=$(front_bundle)
if [[ -n "${FRONT_BEFORE:-}" && -n "${FRONT_AFTER:-}" && "$FRONT_BEFORE" == "$FRONT_AFTER" ]]; then
  log_event "done" "frontmost preserved: $FRONT_AFTER"
else
  log_event "warn" "frontmost changed: ${FRONT_BEFORE:-unknown} -> ${FRONT_AFTER:-unknown}"
  if [[ -n "${FRONT_BEFORE:-}" ]]; then
    "$APP_EXECUTABLE" activate-app --bundle-id "$FRONT_BEFORE" >/dev/null || true
  fi
fi

printf 'Trace: %s\n' "$TRACE_FILE"
printf 'Artifacts: %s\n' "$OUTPUT_DIR"
printf 'Preview: %s\n' "$PREVIEW_IMAGE"
printf 'Moondream: %s\n' "$MOONDREAM_JSON"
if [[ -n "$NEW_REF" ]]; then
  printf 'New image: %s\n' "$NEW_REF"
elif [[ "$MOONDREAM_RENDERED" == "true" ]]; then
  printf 'Rendered: Moondream verified screenshot\n'
elif [[ -n "$RESULT_JSON" ]]; then
  printf 'Rendered: prompt visible with image cards\n'
else
  exit 1
fi
