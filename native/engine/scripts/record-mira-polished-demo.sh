#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
APP_EXECUTABLE="$ROOT_DIR/native/dist/Action.app/Contents/MacOS/Action"
CHROME_APP_NAME="${ACTION_CHROME_APP_NAME:-Google Chrome}"
DEBUG_PORT="${ACTION_MIRA_DEBUG_PORT:-9335}"
PROFILE_DIR="${ACTION_MIRA_PROFILE_DIR:-$HOME/Library/Application Support/Action/ChromeProfiles/mira}"
OUTPUT_DIR="${ACTION_MIRA_DEMO_OUTPUT_DIR:-$ROOT_DIR/artifacts/captures/mira-polished-demo-$(date +%Y%m%d-%H%M%S)}"
FPS="${ACTION_MIRA_DEMO_FPS:-15}"
SCALE="${ACTION_MIRA_DEMO_SCALE:-1}"
SUBMIT_MIDJOURNEY="${ACTION_MIRA_DEMO_SUBMIT_MIDJOURNEY:-1}"
START_URL="${ACTION_MIRA_DEMO_START_URL:-about:blank}"
MIN_INTERACTION_MS="${ACTION_MIRA_DEMO_MIN_INTERACTION_MS:-1250}"
MIN_TYPING_MS="${ACTION_MIRA_DEMO_MIN_TYPING_MS:-1120}"
REAL_CLICKS="${ACTION_MIRA_DEMO_REAL_CLICKS:-0}"
GOOGLE_QUERY="${ACTION_MIRA_DEMO_GOOGLE_QUERY:-macOS agent capture demo}"
MIDJOURNEY_PROMPT="${ACTION_MIRA_DEMO_MIDJOURNEY_PROMPT:-refined logo mark for Action macOS app, abstract A formed by cursor arrow negative space, electric cyan stroke, coral recording dot, capture corner ticks, graphite black, warm off-white background, no words}"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  "$SCRIPT_DIR/build-app.sh" >/dev/stderr
fi

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$ROOT_DIR/$OUTPUT_DIR" ;;
esac

mkdir -p "$OUTPUT_DIR" "$PROFILE_DIR"

MOV_PATH="$OUTPUT_DIR/action-mira-polished-demo.mov"
NARRATED_MP4="$OUTPUT_DIR/action-mira-polished-demo-narrated.mp4"
STOP_FILE="$MOV_PATH.stop"
FINISHED_FILE="$MOV_PATH.finished"
DEBUG_LOG="$MOV_PATH.log"
RECORD_REPLY="$OUTPUT_DIR/record-start.json"
FRAME_JSON="$OUTPUT_DIR/mira-frame.json"
TRACE_FILE="$OUTPUT_DIR/demo-trace.log"
AUDIO_CUES_JSONL="$OUTPUT_DIR/audio-cues.jsonl"
STATUS_JSON="$OUTPUT_DIR/midjourney-status.json"
PROMPT_JSON="$OUTPUT_DIR/midjourney-prompt.json"
FINAL_SCREENSHOT="$OUTPUT_DIR/final.png"
ACTIVE_TARGET_ID_FILE="$OUTPUT_DIR/active-chrome-target-id"

rm -f "$MOV_PATH" "$STOP_FILE" "$FINISHED_FILE" "$DEBUG_LOG" "$RECORD_REPLY" \
  "$FRAME_JSON" "$TRACE_FILE" "$AUDIO_CUES_JSONL" "$STATUS_JSON" "$PROMPT_JSON" \
  "$FINAL_SCREENSHOT" "$ACTIVE_TARGET_ID_FILE"

RECORDING_STARTED_MS=""

log_event() {
  local kind="$1"
  local text="$2"
  printf '%s|%s\n' "$kind" "$text" >> "$TRACE_FILE"
  printf '[%s] %s\n' "$kind" "$text"
}

now_ms() {
  bun -e 'console.log(Date.now())'
}

audio_cue() {
  local kind="$1"
  local duration_ms="$2"
  local detail="$3"
  if [[ -z "$RECORDING_STARTED_MS" ]]; then
    return
  fi
  local at_ms
  at_ms=$(( $(now_ms) - RECORDING_STARTED_MS ))
  KIND="$kind" AT_MS="$at_ms" DURATION_MS="$duration_ms" DETAIL="$detail" bun -e '
    const cue = {
      kind: process.env.KIND,
      atMs: Number(process.env.AT_MS),
      durationMs: Number(process.env.DURATION_MS),
      detail: process.env.DETAIL || "",
    };
    console.log(JSON.stringify(cue));
  ' >> "$AUDIO_CUES_JSONL"
}

max_ms() {
  local left="$1"
  local right="$2"
  if (( left > right )); then
    echo "$left"
  else
    echo "$right"
  fi
}

sleep_ms() {
  local ms="$1"
  local seconds
  seconds=$(MS="$ms" bun -e 'const ms = Math.max(0, Number(process.env.MS) || 0); console.log((ms / 1000).toFixed(3));')
  sleep "$seconds"
}

mira_pid() {
  pgrep -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=.*ChromeProfiles/mira" | head -1 || true
}

activate_mira() {
  local pid
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    return 0
  fi

  /usr/bin/osascript - "$pid" <<'APPLESCRIPT' >/dev/null
use framework "AppKit"
use scripting additions
on run argv
  set targetPid to (item 1 of argv) as integer
  set appRef to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:targetPid
  if appRef is not missing value then
    appRef's activateWithOptions:(current application's NSApplicationActivateIgnoringOtherApps)
  end if
end run
APPLESCRIPT
  sleep 0.35
}

ensure_mira() {
  if curl -fsS "http://127.0.0.1:$DEBUG_PORT/json/version" >/dev/null 2>&1; then
    activate_mira
    return
  fi

  open -n -a "$CHROME_APP_NAME" --args \
    "--user-data-dir=$PROFILE_DIR" \
    "--no-first-run" \
    "--no-default-browser-check" \
    "--remote-debugging-port=$DEBUG_PORT" \
    --new-window "about:blank"
  sleep 2.4
  activate_mira
}

open_fresh_chrome_tab() {
  local url="${1:-about:blank}"
  if [[ -z "$url" ]]; then
    return
  fi
  local target_id
  target_id=$(DEBUG_PORT="$DEBUG_PORT" START_URL="$url" bun - <<'BUN' 2>/dev/null || true
const port = process.env.DEBUG_PORT;
const startURL = process.env.START_URL || "about:blank";
const opened = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(startURL)}`, {
  method: "PUT",
}).then((response) => response.json()).catch(() => null);
await Bun.sleep(350);
const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then((response) => response.json()).catch(() => []);
const keepId = opened?.id;
for (const target of targets) {
  if (target.type === "page" && target.id && target.id !== keepId) {
    await fetch(`http://127.0.0.1:${port}/json/close/${target.id}`, {
      method: "PUT",
    }).catch(() => undefined);
  }
}
if (keepId) {
  await fetch(`http://127.0.0.1:${port}/json/activate/${keepId}`, {
    method: "PUT",
  }).catch(() => undefined);
  console.log(keepId);
}
BUN
)
  if [[ -n "$target_id" ]]; then
    printf '%s\n' "$target_id" > "$ACTIVE_TARGET_ID_FILE"
    log_event "browser" "fresh visible target: $url ($target_id)"
  else
    log_event "browser" "fresh visible target requested: $url"
  fi
  sleep 0.8
  activate_mira
}

prepare_start_surface() {
  open_fresh_chrome_tab "$START_URL"
}

ensure_browser_url() {
  local url="$1"
  local target_id=""
  if [[ -f "$ACTIVE_TARGET_ID_FILE" ]]; then
    target_id=$(cat "$ACTIVE_TARGET_ID_FILE")
  fi
  DEBUG_PORT="$DEBUG_PORT" TARGET_URL="$url" TARGET_ID="$target_id" bun - <<'BUN' >/dev/null 2>&1 || true
const port = process.env.DEBUG_PORT;
const rawURL = process.env.TARGET_URL || "about:blank";
const targetId = process.env.TARGET_ID || "";
const targetURL = /^[a-z][a-z0-9+.-]*:/i.test(rawURL) ? rawURL : `https://${rawURL}`;
const targets = await fetch(`http://127.0.0.1:${port}/json/list`)
  .then((response) => response.json())
  .catch(() => []);
const page = targets.find((target) => target.id === targetId && target.type === "page" && target.webSocketDebuggerUrl)
  ?? targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
if (!page?.webSocketDebuggerUrl) {
  process.exit(0);
}
if (page.id) {
  await fetch(`http://127.0.0.1:${port}/json/activate/${page.id}`, {
    method: "PUT",
  }).catch(() => undefined);
}

let nextId = 1;
const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});

await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(message.error.message));
  else waiter.resolve(message.result);
});

await send("Page.enable");
await send("Page.navigate", { url: targetURL });
await new Promise((resolve) => setTimeout(resolve, 900));
socket.close();
BUN
  log_event "act" "CDP committed fresh-tab URL: $url"
}

write_mira_frame() {
  local pid
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    echo "Mira Chrome profile is not running." >&2
    exit 2
  fi

  MIRA_PID="$pid" swift - > "$FRAME_JSON" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int(ProcessInfo.processInfo.environment["MIRA_PID"] ?? "") ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = windows.first { item in
    (item[kCGWindowOwnerPID as String] as? Int) == pid
        && (item[kCGWindowLayer as String] as? Int ?? 0) == 0
        && ((item[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 400
}

guard let match,
      let bounds = match[kCGWindowBounds as String] as? [String: Any] else {
    fputs("Unable to resolve Mira Chrome window frame.\n", stderr)
    exit(1)
}

let frame: [String: Any] = [
    "x": bounds["X"] ?? 0,
    "y": bounds["Y"] ?? 0,
    "width": bounds["Width"] ?? 0,
    "height": bounds["Height"] ?? 0,
]
let payload: [String: Any] = [
    "pid": pid,
    "windowId": match[kCGWindowNumber as String] ?? 0,
    "title": match[kCGWindowName as String] ?? "",
    "frame": frame,
    "screenHeight": CGDisplayBounds(CGMainDisplayID()).height,
]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
SWIFT
}

frame_value() {
  local expr="$1"
  STATUS_PATH="$FRAME_JSON" bun -e "const data = await Bun.file(process.env.STATUS_PATH).json(); console.log(Math.round($expr));"
}

point_json() {
  local rel_x="$1"
  local rel_y="$2"
  STATUS_PATH="$FRAME_JSON" REL_X="$rel_x" REL_Y="$rel_y" bun -e 'const data = await Bun.file(process.env.STATUS_PATH).json(); const rx=Number(process.env.REL_X); const ry=Number(process.env.REL_Y); console.log(JSON.stringify({ x: Math.round(data.frame.x + data.frame.width * rx), y: Math.round(data.frame.y + data.frame.height * ry) }));'
}

point_x() {
  POINT_JSON="$1" bun -e 'console.log(JSON.parse(process.env.POINT_JSON).x)'
}

point_y() {
  POINT_JSON="$1" bun -e 'console.log(JSON.parse(process.env.POINT_JSON).y)'
}

overlay_point_json() {
  local point="$1"
  FRAME_PATH="$FRAME_JSON" POINT_JSON="$point" bun -e '
    const data = await Bun.file(process.env.FRAME_PATH).json();
    const point = JSON.parse(process.env.POINT_JSON);
    const screenHeight = Number(data.screenHeight ?? (data.frame.y + data.frame.height));
    console.log(JSON.stringify({
      x: Math.round(point.x),
      y: Math.round(screenHeight - point.y),
    }));
  '
}

prompt_point_json() {
  FRAME_PATH="$FRAME_JSON" PROMPT_PATH="$PROMPT_JSON" bun -e '
    const frameData = await Bun.file(process.env.FRAME_PATH).json();
    const prompt = await Bun.file(process.env.PROMPT_PATH).json();
    if (!prompt.ok || !prompt.rect || !prompt.viewport) {
      process.exit(2);
    }
    const chromeTop = Math.max(0, Number(frameData.frame.height) - Number(prompt.viewport.height));
    console.log(JSON.stringify({
      x: Math.round(Number(frameData.frame.x) + Number(prompt.rect.centerX)),
      y: Math.round(Number(frameData.frame.y) + chromeTop + Number(prompt.rect.centerY)),
    }));
  '
}

focus_google_search_field() {
  DEBUG_PORT="$DEBUG_PORT" bun - <<'BUN' >/dev/null 2>&1 || true
const port = process.env.DEBUG_PORT;
const targets = await fetch(`http://127.0.0.1:${port}/json/list`)
  .then((response) => response.json())
  .catch(() => []);
const page = targets.find((target) => target.type === "page" && /google\./i.test(target.url || ""))
  ?? targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
if (!page?.webSocketDebuggerUrl) {
  process.exit(0);
}

let nextId = 1;
const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});

await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(message.error.message));
  else waiter.resolve(message.result);
});

await send("Runtime.evaluate", {
  expression: `
    (() => {
      const input = document.querySelector('textarea[name="q"], input[name="q"], textarea[aria-label], input[aria-label]');
      if (!input) return false;
      input.focus();
      input.select?.();
      return true;
    })()
  `,
  awaitPromise: true,
});
socket.close();
BUN
  sleep 0.25
}

type_google_search_visible() {
  local text="$1"
  local detail="$2"
  local delay_ms="${3:-24}"
  local target_id=""
  local px py duration lead_sleep tail_sleep
  if [[ -f "$ACTIVE_TARGET_ID_FILE" ]]; then
    target_id=$(cat "$ACTIVE_TARGET_ID_FILE")
  fi
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")
  duration=$(( 300 + ${#text} * delay_ms + 260 ))
  duration=$(max_ms "$duration" "$MIN_TYPING_MS")
  lead_sleep=0.10
  tail_sleep=0.18

  log_event "type" "$detail (visible typing, CDP-owned Google input): $text"
  audio_cue "typing" "$duration" "$detail"
  overlay \
    --duration-ms "$duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Typing" \
    --status-detail "$detail" \
    --typing-text "$text" \
    --typing-sound timed \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep "$lead_sleep"
  DEBUG_PORT="$DEBUG_PORT" TARGET_ID="$target_id" QUERY="$text" DELAY_MS="$delay_ms" bun - <<'BUN' > "$STATUS_JSON"
const port = process.env.DEBUG_PORT;
const targetId = process.env.TARGET_ID || "";
const query = process.env.QUERY || "";
const delayMs = Number(process.env.DELAY_MS || 24);
const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then((response) => response.json());
const page = targets.find((target) => target.id === targetId && target.type === "page" && target.webSocketDebuggerUrl)
  ?? targets.find((target) => target.type === "page" && /google\./i.test(target.url || "") && target.webSocketDebuggerUrl)
  ?? targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
if (!page?.webSocketDebuggerUrl) {
  throw new Error("No Chrome page target for Google search");
}
if (page.id) {
  await fetch(`http://127.0.0.1:${port}/json/activate/${page.id}`, { method: "PUT" }).catch(() => undefined);
}

let nextId = 1;
const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(message.error.message));
  else waiter.resolve(message.result || {});
});
await send("Runtime.enable");
await send("Page.enable");
const focused = await send("Runtime.evaluate", {
  expression: `
    (() => {
      const input = document.querySelector('textarea[name="q"], input[name="q"]');
      if (!input) {
        return { ok: false, reason: "Google query input missing", url: location.href, title: document.title };
      }
      input.focus();
      input.select?.();
      if ("value" in input) {
        input.value = "";
        input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContentBackward", data: null }));
      }
      return { ok: true, url: location.href, title: document.title };
    })()
  `,
  awaitPromise: true,
  returnByValue: true,
});
if (!focused.result?.value?.ok) {
  throw new Error(focused.result?.value?.reason || "Unable to focus Google search input");
}
for (const character of query) {
  await send("Input.dispatchKeyEvent", {
    type: "char",
    text: character,
    unmodifiedText: character,
  });
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}
const after = await send("Runtime.evaluate", {
  expression: `
    (() => {
      const input = document.querySelector('textarea[name="q"], input[name="q"]');
      return {
        ok: Boolean(input),
        value: input && "value" in input ? input.value : "",
        activeTag: document.activeElement?.tagName || "",
        activeName: document.activeElement?.getAttribute("name") || "",
        url: location.href,
      };
    })()
  `,
  awaitPromise: true,
  returnByValue: true,
});
socket.close();
console.log(JSON.stringify({ targetId: page.id, focused: focused.result.value, after: after.result.value }, null, 2));
BUN
  sleep "$tail_sleep"
}

press_google_enter_visible() {
  local detail="$1"
  local target_id=""
  local px py cue_duration before_key after_key
  if [[ -f "$ACTIVE_TARGET_ID_FILE" ]]; then
    target_id=$(cat "$ACTIVE_TARGET_ID_FILE")
  fi
  cue_duration=$(max_ms 1100 "$MIN_INTERACTION_MS")
  before_key=$(( cue_duration * 42 / 100 ))
  after_key=$(( cue_duration - before_key + 240 ))
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")

  log_event "act" "key Return: $detail (visible key, CDP-owned Google input)"
  audio_cue "key" "$cue_duration" "$detail"
  overlay \
    --duration-ms "$cue_duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Key" \
    --key-label "Return" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep_ms "$before_key"
  DEBUG_PORT="$DEBUG_PORT" TARGET_ID="$target_id" bun - <<'BUN' > "$STATUS_JSON"
const port = process.env.DEBUG_PORT;
const targetId = process.env.TARGET_ID || "";
const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then((response) => response.json());
const page = targets.find((target) => target.id === targetId && target.type === "page" && target.webSocketDebuggerUrl)
  ?? targets.find((target) => target.type === "page" && /google\./i.test(target.url || "") && target.webSocketDebuggerUrl)
  ?? targets.find((target) => target.type === "page" && target.webSocketDebuggerUrl);
if (!page?.webSocketDebuggerUrl) {
  throw new Error("No Chrome page target for Google search submit");
}
let nextId = 1;
const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(message.error.message));
  else waiter.resolve(message.result || {});
});
await send("Runtime.enable");
await send("Page.enable");
await send("Input.dispatchKeyEvent", {
  type: "keyDown",
  key: "Enter",
  code: "Enter",
  windowsVirtualKeyCode: 13,
  nativeVirtualKeyCode: 36,
});
await send("Input.dispatchKeyEvent", {
  type: "keyUp",
  key: "Enter",
  code: "Enter",
  windowsVirtualKeyCode: 13,
  nativeVirtualKeyCode: 36,
});
await new Promise((resolve) => setTimeout(resolve, 900));
const after = await send("Runtime.evaluate", {
  expression: `({ url: location.href, title: document.title, textSample: document.body?.innerText?.replace(/\\s+/g, " ").slice(0, 220) || "" })`,
  awaitPromise: true,
  returnByValue: true,
});
socket.close();
console.log(JSON.stringify({ targetId: page.id, after: after.result.value }, null, 2));
BUN
  sleep_ms "$after_key"
}

overlay() {
  "$SCRIPT_DIR/run-app-host.sh" demo-cursor-overlay "$@" >/dev/null 2>&1 &
}

status_overlay() {
  local label="$1"
  local duration="$2"
  local detail="$3"
  duration=$(max_ms "$duration" "$MIN_INTERACTION_MS")
  overlay \
    --duration-ms "$duration" \
    --label "$label" \
    --status-detail "$detail" \
    --status-only true \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
}

mira_near_target_point() {
  local target="$1"
  local dx="${2:-180}"
  local dy="${3:-128}"
  FRAME_PATH="$FRAME_JSON" TARGET_JSON="$target" DX="$dx" DY="$dy" bun -e '
    const frameData = await Bun.file(process.env.FRAME_PATH).json();
    const target = JSON.parse(process.env.TARGET_JSON);
    const frame = frameData.frame;
    const requestedDx = Number(process.env.DX);
    const requestedDy = Number(process.env.DY);
    const dx = requestedDx > 0 && target.x + requestedDx > frame.x + frame.width - 190
      ? -235
      : requestedDx;
    const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
    console.log(JSON.stringify({
      x: Math.round(clamp(target.x + dx, frame.x + 110, frame.x + frame.width - 115)),
      y: Math.round(clamp(target.y + requestedDy, frame.y + 94, frame.y + frame.height - 150)),
    }));
  '
}

move_mira_near_target() {
  local target="$1"
  local dx="${2:-180}"
  local dy="${3:-128}"
  local duration_ms="${4:-760}"
  local point mx my
  point=$(mira_near_target_point "$target" "$dx" "$dy")
  local overlay_point
  overlay_point=$(overlay_point_json "$point")
  mx=$(point_x "$overlay_point")
  my=$(point_y "$overlay_point")
  bun scripts/mira-overlay.mjs move "$mx" "$my" "$duration_ms" >/dev/null 2>&1 || true
}

move_mira_near_rel() {
  local rel_x="$1"
  local rel_y="$2"
  local dx="${3:-180}"
  local dy="${4:-128}"
  local duration_ms="${5:-760}"
  local target
  target=$(point_json "$rel_x" "$rel_y")
  move_mira_near_target "$target" "$dx" "$dy" "$duration_ms"
}

place_mira() {
  local message="$1"
  local rel_x="${2:-0.42}"
  local rel_y="${3:-0.035}"
  local duration_ms="${4:-1600}"
  local dx="${5:-180}"
  local dy="${6:-128}"
  move_mira_near_rel "$rel_x" "$rel_y" "$dx" "$dy" "$duration_ms"
}

LAST_POINT=""

click_visible_target() {
  local target="$1"
  local label="$3"
  local detail="$4"
  local mira_dx="${5:-180}"
  local mira_dy="${6:-128}"
  local mira_duration="${7:-620}"
  local start_overlay end_overlay sx sy ex ey click_x click_y cue_duration before_click after_click
  cue_duration=$(max_ms 1180 "$MIN_INTERACTION_MS")
  before_click=$(( cue_duration * 68 / 100 ))
  after_click=$(( cue_duration - before_click + 220 ))
  start_overlay=$(overlay_point_json "$LAST_POINT")
  end_overlay=$(overlay_point_json "$target")
  sx=$(point_x "$start_overlay")
  sy=$(point_y "$start_overlay")
  ex=$(point_x "$target")
  ey=$(point_y "$target")
  click_x="$ex"
  click_y="$ey"
  ex=$(point_x "$end_overlay")
  ey=$(point_y "$end_overlay")

  log_event "guide" "$label cursor cue: $detail"
  move_mira_near_target "$target" "$mira_dx" "$mira_dy" "$mira_duration"
  overlay \
    --duration-ms "$cue_duration" \
    --start-x "$sx" \
    --start-y "$sy" \
    --end-x "$ex" \
    --end-y "$ey" \
    --click-progress 0.68 \
    --label "$label" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep_ms "$before_click"
  if [[ "$REAL_CLICKS" == "1" ]]; then
    "$SCRIPT_DIR/run-app-host.sh" click-point --x "$click_x" --y "$click_y" >/dev/null
  else
    log_event "act" "virtual click only: $detail"
  fi
  sleep_ms "$after_click"
  LAST_POINT="$target"
}

click_visible() {
  local rel_x="$1"
  local rel_y="$2"
  local label="$3"
  local detail="$4"
  local mira_dx="${5:-180}"
  local mira_dy="${6:-128}"
  local mira_duration="${7:-620}"
  local target
  target=$(point_json "$rel_x" "$rel_y")
  click_visible_target "$target" "$rel_x" "$label" "$detail" "$mira_dx" "$mira_dy" "$mira_duration"
}

type_visible() {
  local text="$1"
  local detail="$2"
  local delay_ms="${3:-22}"
  local pid px py duration lead_sleep tail_sleep
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    echo "Mira Chrome profile is not running." >&2
    exit 2
  fi
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")
  if (( ${#text} > 80 )); then
    duration=$(( ${#text} * delay_ms + 90 ))
    lead_sleep=0.02
    tail_sleep=0.08
  else
    duration=$(( 300 + ${#text} * delay_ms + 260 ))
    duration=$(max_ms "$duration" "$MIN_TYPING_MS")
    lead_sleep=0.10
    tail_sleep=0.18
  fi

  log_event "type" "$detail (visualized for the viewer): $text"
  audio_cue "typing" "$duration" "$detail"
  overlay \
    --duration-ms "$duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Typing" \
    --status-detail "$detail" \
    --typing-text "$text" \
    --typing-sound timed \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep "$lead_sleep"
  "$SCRIPT_DIR/run-app-host.sh" type-pid-text --pid "$pid" --text "$text" --delay-ms "$delay_ms" >/dev/null
  sleep "$tail_sleep"
}

type_visible_cue_only() {
  local text="$1"
  local detail="$2"
  local delay_ms="${3:-18}"
  local px py duration lead_sleep tail_sleep
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")
  duration=$(( 300 + ${#text} * delay_ms + 260 ))
  duration=$(max_ms "$duration" "$MIN_TYPING_MS")
  lead_sleep=0.10
  tail_sleep=0.18

  log_event "type" "$detail (visible teaching cue only): $text"
  audio_cue "typing" "$duration" "$detail"
  overlay \
    --duration-ms "$duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Typing" \
    --status-detail "$detail" \
    --typing-text "$text" \
    --typing-sound timed \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep "$lead_sleep"
  sleep "$tail_sleep"
}

type_midjourney_prompt_visible() {
  local text="$1"
  local detail="$2"
  local delay_ms="${3:-16}"
  local px py duration lead_sleep tail_sleep
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")
  duration=$(( ${#text} * delay_ms + 360 ))
  duration=$(max_ms "$duration" "$MIN_TYPING_MS")
  lead_sleep=0.10
  tail_sleep=0.20

  log_event "type" "$detail (visible typing, CDP-owned state): $text"
  audio_cue "typing" "$duration" "$detail"
  overlay \
    --duration-ms "$duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Typing" \
    --status-detail "$detail" \
    --typing-text "$text" \
    --typing-sound timed \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep "$lead_sleep"
  "$SCRIPT_DIR/mira-midjourney-cdp.mjs" type-prompt \
    --debug-port "$DEBUG_PORT" \
    --prompt "$text" \
    --delay-ms "$delay_ms" \
    --wait-ms 12000 > "$PROMPT_JSON"
  sleep "$tail_sleep"
}

key_visible() {
  local key="$1"
  local detail="$2"
  local modifiers="${3:-}"
  local pid px py cue_duration before_key after_key
  cue_duration=$(max_ms 1100 "$MIN_INTERACTION_MS")
  before_key=$(( cue_duration * 42 / 100 ))
  after_key=$(( cue_duration - before_key + 240 ))
  pid=$(mira_pid)
  if [[ -z "$pid" ]]; then
    echo "Mira Chrome profile is not running." >&2
    exit 2
  fi
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")

  log_event "act" "key $key: $detail"
  audio_cue "key" "$cue_duration" "$detail"
  overlay \
    --duration-ms "$cue_duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Key" \
    --key-label "$key" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep_ms "$before_key"
  if [[ -n "$modifiers" ]]; then
    "$SCRIPT_DIR/run-app-host.sh" press-pid-key --pid "$pid" --key "$key" --modifiers "$modifiers" >/dev/null
  else
    "$SCRIPT_DIR/run-app-host.sh" press-pid-key --pid "$pid" --key "$key" >/dev/null
  fi
  sleep_ms "$after_key"
}

press_midjourney_enter_visible() {
  local detail="$1"
  local px py cue_duration before_key after_key
  cue_duration=$(max_ms 1100 "$MIN_INTERACTION_MS")
  before_key=$(( cue_duration * 42 / 100 ))
  after_key=$(( cue_duration - before_key + 240 ))
  local overlay_point
  overlay_point=$(overlay_point_json "$LAST_POINT")
  px=$(point_x "$overlay_point")
  py=$(point_y "$overlay_point")

  log_event "act" "key Return: $detail (visible key, CDP-owned state)"
  audio_cue "key" "$cue_duration" "$detail"
  overlay \
    --duration-ms "$cue_duration" \
    --start-x "$px" \
    --start-y "$py" \
    --end-x "$px" \
    --end-y "$py" \
    --click-progress 0.50 \
    --label "Key" \
    --key-label "Return" \
    --status-detail "$detail" \
    --trace-file "$TRACE_FILE" \
    --trace-title "Mira / Action loop"
  sleep_ms "$before_key"
  "$SCRIPT_DIR/mira-midjourney-cdp.mjs" press-enter --debug-port "$DEBUG_PORT" --wait-ms 12000 > "$STATUS_JSON"
  sleep_ms "$after_key"
}

navigate_omnibox() {
  local url="$1"
  open_fresh_chrome_tab "about:blank"
  write_mira_frame
  click_visible 0.42 0.035 "Resolve" "AX target: Chrome omnibox"
  type_visible_cue_only "$url" "address-bar typing cue; CDP owns navigation" 18
  ensure_browser_url "$url"
  sleep 0.7
}

inspect_midjourney() {
  if "$SCRIPT_DIR/mira-midjourney-cdp.mjs" status --debug-port "$DEBUG_PORT" > "$STATUS_JSON" 2>/dev/null; then
    local summary
    summary=$(STATUS_PATH="$STATUS_JSON" bun -e 'const s = await Bun.file(process.env.STATUS_PATH).json(); console.log(`promptReady=${s.promptReady} imageCount=${s.imageCount}`);')
    log_event "inspect" "browser state: $summary"
    status_overlay "Inspect" 1500 "$summary"
    sleep 1.1
  else
    log_event "inspect" "browser state unavailable"
    status_overlay "Inspect" 1500 "browser state unavailable"
    sleep 1.1
  fi
}

prepare_midjourney_prompt() {
  key_visible "Escape" "close transient Midjourney panel"
  sleep 0.45

  if "$SCRIPT_DIR/mira-midjourney-cdp.mjs" prepare-prompt --debug-port "$DEBUG_PORT" > "$PROMPT_JSON" 2>/dev/null; then
    local summary
    summary=$(STATUS_PATH="$PROMPT_JSON" bun -e 'const s = await Bun.file(process.env.STATUS_PATH).json(); if (s.ok) console.log(`prompt rect ${s.rect.width}x${s.rect.height}`); else console.log(s.reason || "prompt unavailable");')
    log_event "inspect" "prompt target: $summary"
    status_overlay "Inspect" 1450 "$summary"
    sleep 1.0
  else
    log_event "inspect" "prompt target unavailable"
    status_overlay "Inspect" 1450 "prompt target unavailable"
    sleep 1.0
  fi
}

ensure_mira
prepare_start_surface
write_mira_frame
REGION_X=$(frame_value "data.frame.x")
REGION_Y=$(frame_value "data.frame.y")
REGION_W=$(frame_value "data.frame.width")
REGION_H=$(frame_value "data.frame.height")
LAST_POINT=$(point_json 0.86 0.74)

log_event "goal" "Mira creates a visual direction while Action records and inspects"
log_event "policy" "control lanes: VLM/browser observation, AX/CDP target resolution, process-directed input, cursor and typing overlays for viewer education"

bun scripts/mira-overlay.mjs hide >/dev/null 2>&1 || true
sleep 0.15
if bun scripts/mira-overlay.mjs show --no-message >/dev/null 2>&1; then
  place_mira "Mira is guiding the control lanes." 0.42 0.035 900 180 128
  log_event "overlay" "Mira character shown through Lattices"
else
  log_event "overlay" "Mira character unavailable; continuing with Action overlay"
fi

"$SCRIPT_DIR/run-app-host.sh" record-region \
  --x "$REGION_X" \
  --y "$REGION_Y" \
  --width "$REGION_W" \
  --height "$REGION_H" \
  --fps "$FPS" \
  --scale "$SCALE" \
  --output "$MOV_PATH" \
  --stop-file "$STOP_FILE" \
  --finished-file "$FINISHED_FILE" \
  --debug-log "$DEBUG_LOG" > "$RECORD_REPLY"
RECORDING_STARTED_MS=$(now_ms)

sleep 0.8
activate_mira
  status_overlay "Mira" 1700 "VLM sees · AX resolves · native input acts"
sleep 1.2

log_event "surface" "Google is the legible browser surface"
place_mira "First: observe the browser surface." 0.42 0.035 900 180 128
navigate_omnibox "google.com"
sleep 1.2
click_visible 0.50 0.37 "Resolve" "visual cue: Google search field" 125 95 780
type_google_search_visible "$GOOGLE_QUERY" "CDP Google input, dramatized typing" 24
press_google_enter_visible "submit Google search"
sleep 2.2
status_overlay "Observe" 1400 "search results loaded"
log_event "observe" "Google results loaded for: $GOOGLE_QUERY"
sleep 0.8

log_event "surface" "Midjourney is the visual payoff surface"
place_mira "Then: resolve a creative surface." 0.42 0.035 900 180 128
navigate_omnibox "midjourney.com/imagine"
sleep 3.0
inspect_midjourney
place_mira "CDP resolves the prompt; native input does the work." 0.48 0.092 1000 150 165
prepare_midjourney_prompt
if prompt_target=$(prompt_point_json 2>/dev/null); then
  click_visible_target "$prompt_target" "prompt" "Resolve" "CDP target: What will you imagine?" 150 165 1000
else
  click_visible 0.48 0.092 "Resolve" "visual cue: What will you imagine?" 150 165 1000
fi
type_midjourney_prompt_visible "$MIDJOURNEY_PROMPT" "CDP prompt input, dramatized typing" 16
inspect_midjourney

if [[ "$SUBMIT_MIDJOURNEY" == "1" ]]; then
  press_midjourney_enter_visible "submit prompt"
  sleep 6.0
  inspect_midjourney
else
  log_event "pause" "prompt staged; submit disabled by ACTION_MIRA_DEMO_SUBMIT_MIDJOURNEY=0"
  status_overlay "Staged" 2200 "submit disabled by env"
  sleep 1.8
fi

status_overlay "Artifact" 1800 "video + trace + finished marker"
place_mira "Finally: the run becomes an artifact." 0.79 0.16 1200 -220 82
log_event "artifact" "recording will finish with marker and final screenshot"
sleep 1.3

"$SCRIPT_DIR/run-app-host.sh" screenshot-region \
  --x "$REGION_X" \
  --y "$REGION_Y" \
  --width "$REGION_W" \
  --height "$REGION_H" \
  --output "$FINAL_SCREENSHOT" >/dev/null

printf 'stop\n' > "$STOP_FILE"
for _ in {1..240}; do
  if [[ -s "$FINISHED_FILE" ]]; then
    break
  fi
  sleep 0.1
done

bun scripts/mira-overlay.mjs hide >/dev/null 2>&1 || true

if [[ ! -s "$FINISHED_FILE" ]]; then
  echo "Timed out waiting for recording completion marker: $FINISHED_FILE" >&2
  exit 1
fi

if grep -q '^error:' "$FINISHED_FILE"; then
  cat "$FINISHED_FILE" >&2
  exit 1
fi

if [[ "${ACTION_MIRA_DEMO_NARRATE:-0}" != "0" ]]; then
  if secret get ELEVENLABS_API_KEY >/dev/null 2>&1 || [[ -n "${ELEVENLABS_API_KEY:-}" ]]; then
    if "$SCRIPT_DIR/render-elevenlabs-narration.mjs" \
      --video "$MOV_PATH" \
      --output "$NARRATED_MP4" \
      --work-dir "$OUTPUT_DIR/narration"; then
      echo "[done] narrated-video: $NARRATED_MP4"
    else
      echo "[warn] ElevenLabs narration failed; raw recording is still complete." >&2
    fi
  else
    echo "[skip] ELEVENLABS_API_KEY unavailable; narration was not rendered." >&2
  fi
fi

echo "[done] recording: $MOV_PATH"
echo "[done] finished-marker: $FINISHED_FILE"
echo "[done] trace: $TRACE_FILE"
echo "[done] final-screenshot: $FINAL_SCREENSHOT"
ls -lh "$MOV_PATH" "$FINAL_SCREENSHOT" "$TRACE_FILE"
if [[ -f "$NARRATED_MP4" ]]; then
  ls -lh "$NARRATED_MP4"
fi
