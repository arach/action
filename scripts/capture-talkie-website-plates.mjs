#!/usr/bin/env node
import { chmodSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync as execFile, spawn } from "node:child_process";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const HOST = resolve(ROOT, "native/dist/Action.app/Contents/MacOS/Action");
const OUT_DIR = resolve(ROOT, "artifacts/action-demos");
const TERMINAL_DIR = resolve(OUT_DIR, "terminal-fixtures");
const DEFAULT_TALKIE_BUNDLE_ID = "to.talkie.app.mac.dev";
const REMOVED_TALKIE_CORE_BUNDLE_ID = ["jdi", "talkie", "core"].join(".");
const FORBIDDEN_BUNDLE_IDS = new Set([REMOVED_TALKIE_CORE_BUNDLE_ID]);
const TALKIE_BUNDLE = process.env.TALKIE_BUNDLE_ID ?? DEFAULT_TALKIE_BUNDLE_ID;

if (FORBIDDEN_BUNDLE_IDS.has(TALKIE_BUNDLE)) {
  throw new Error(`Refusing to target removed Talkie bundle id: ${TALKIE_BUNDLE}`);
}
const ACTION_BUNDLE = "dev.action.Action";

const sleep = (ms) => new Promise((resolveSleep) => setTimeout(resolveSleep, ms));

function run(args, { allowFailure = false, parseJson = false } = {}) {
  try {
    const output = execFile(HOST, args, {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return parseJson ? JSON.parse(output) : output;
  } catch (error) {
    if (allowFailure) return parseJson ? null : "";
    throw error;
  }
}

function press(label, role = "AXButton", allowFailure = false) {
  run([
    "press-accessibility-element",
    "--bundle-id", TALKIE_BUNDLE,
    "--label", label,
    "--role", role,
  ], { allowFailure });
}

function click(x, y) {
  run(["click-point", "--x", String(x), "--y", String(y)]);
}

function setRoleValue(role, value) {
  run([
    "set-accessibility-role-value",
    "--bundle-id", TALKIE_BUNDLE,
    "--role", role,
    "--value", value,
  ]);
}

function key(keyName, bundleId = TALKIE_BUNDLE, allowFailure = false) {
  run([
    "press-app-key",
    "--bundle-id", bundleId,
    "--key", keyName,
  ], { allowFailure });
}

async function prepareTalkieWindow() {
  run(["get-window-frame", "--bundle-id", TALKIE_BUNDLE]);
  run(["activate-app", "--bundle-id", TALKIE_BUNDLE], { allowFailure: true });
  await sleep(250);
  run([
    "set-window-frame",
    "--bundle-id", TALKIE_BUNDLE,
    "--x", "420",
    "--y", "96",
    "--width", "1320",
    "--height", "1180",
  ], { allowFailure: true });
  await sleep(450);
  press("Cancel", "AXButton", true);
  press("Close", "AXButton", true);
  key("Escape", TALKIE_BUNDLE, true);
  await sleep(250);
}

function freshPaths(id) {
  mkdirSync(OUT_DIR, { recursive: true });
  const output = resolve(OUT_DIR, `${id}.mov`);
  const stop = `${output}.stop`;
  const finished = `${output}.finished`;
  const log = `${output}.log`;
  for (const path of [output, stop, finished, log]) {
    rmSync(path, { force: true });
  }
  return { output, stop, finished, log };
}

function startAppWindowRecording(id) {
  const paths = freshPaths(id);
  const child = spawn(HOST, [
    "record-app-window",
    "--bundle-id", TALKIE_BUNDLE,
    "--fps", "30",
    "--output", paths.output,
    "--stop-file", paths.stop,
    "--finished-file", paths.finished,
    "--debug-log", paths.log,
    "--scale", "1",
  ], {
    cwd: ROOT,
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => process.stdout.write(chunk));
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));
  return { ...paths, child };
}

function startRegionRecording(id, frame) {
  const paths = freshPaths(id);
  const child = spawn(HOST, [
    "record-region",
    "--x", String(frame.x),
    "--y", String(frame.y),
    "--width", String(frame.width),
    "--height", String(frame.height),
    "--fps", "30",
    "--output", paths.output,
    "--stop-file", paths.stop,
    "--finished-file", paths.finished,
    "--debug-log", paths.log,
    "--scale", "1",
  ], {
    cwd: ROOT,
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => process.stdout.write(chunk));
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));
  return { ...paths, child };
}

async function stopRecording(recording) {
  writeFileSync(recording.stop, "stop\n");
  const exitCode = await new Promise((resolveClose, reject) => {
    recording.child.once("error", reject);
    recording.child.once("close", resolveClose);
  });
  if (exitCode !== 0) {
    throw new Error(`Recording process exited with ${exitCode}`);
  }
  if (!existsSync(recording.finished)) {
    throw new Error(`Missing finished marker: ${recording.finished}`);
  }
  return recording.output;
}

async function captureTalkieApp(id, setup, steps) {
  await prepareTalkieWindow();
  await setup();
  const recording = startAppWindowRecording(id);
  await sleep(1000);
  for (const step of steps) {
    await step();
  }
  await sleep(700);
  const output = await stopRecording(recording);
  console.log(`captured ${output}`);
  return output;
}

function writeExecutable(path, content) {
  writeFileSync(path, content);
  chmodSync(path, 0o755);
}

function prepareTerminalFixtures() {
  mkdirSync(TERMINAL_DIR, { recursive: true });
  const binDir = resolve(TERMINAL_DIR, "bin");
  mkdirSync(binDir, { recursive: true });

  writeExecutable(resolve(binDir, "talkie"), `#!/bin/sh
cmd="$1"
shift || true
case "$cmd" in
  search)
    cat <<'JSON'
[
  {
    "id": "dic_7f3",
    "type": "dictation",
    "app": "Codex",
    "age": "3d",
    "score": 0.91,
    "text": "What does the Codex computer use do?",
    "context": "frontmost app: Codex; project: /Users/art/dev/action"
  },
  {
    "id": "dic_9aa",
    "type": "dictation",
    "app": "Codex",
    "age": "3d",
    "score": 0.87,
    "text": "If you end up using Codex computer use, that's also cheating.",
    "context": "frontmost app: Codex; project: /Users/art/dev/action"
  }
]
JSON
    ;;
  memos)
    cat <<'JSON'
[
  {
    "id": "memo_agent_loop",
    "title": "Patch the video tab",
    "text": "The queue is useful now, but videos need a completed-treatment shelf. Ask Claude Code to trace the state and patch it.",
    "createdAt": "2026-05-12T18:42:00Z"
  }
]
JSON
    ;;
  workflows)
    cat <<'JSON'
[
  {
    "workflowName": "Voice -> Claude Code",
    "status": "completed",
    "output": "branch codex/preframe-video-tab ready for review"
  },
  {
    "workflowName": "Voice -> Markdown Brief",
    "status": "completed",
    "output": "~/Documents/Talkie/Inbox/2026-05-12-agent-loop.md"
  }
]
JSON
    ;;
  *)
    if [ -n "$TALKIE_REAL_CLI" ]; then
      exec "$TALKIE_REAL_CLI" "$cmd" "$@"
    fi
    echo "Unsupported talkie fixture command: $cmd" >&2
    exit 127
    ;;
esac
`);

  writeExecutable(resolve(binDir, "claude"), `#!/bin/sh
echo "Claude Code"
sleep 0.25
echo "Reading Talkie context: memo_agent_loop, dic_7f3"
sleep 0.45
echo "Inspecting packages/runtime and app queue state..."
sleep 0.55
echo "Patch plan:"
sleep 0.25
echo "  1. Persist completed treatments in the video index."
sleep 0.25
echo "  2. Add a Videos tab empty/success state."
sleep 0.25
echo "  3. Link queue jobs to completed treatments."
sleep 0.45
echo "Result: branch codex/preframe-video-tab ready for review"
`);

  const shellPath = resolve(TERMINAL_DIR, "talkie-demo-shell.sh");
  writeExecutable(shellPath, `#!/bin/sh
export PATH="${binDir}:/Users/art/.bun/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PS1="talkie-demo$ "
export PROMPT="talkie-demo %1~ %# "
exec /bin/zsh -f
`);

  return shellPath;
}

async function startTerminalSession(id) {
  const shellPath = prepareTerminalFixtures();
  const control = resolve(TERMINAL_DIR, `${id}.control`);
  const stop = resolve(TERMINAL_DIR, `${id}.stop`);
  const reply = resolve(TERMINAL_DIR, `${id}.reply.json`);
  for (const path of [control, stop, reply]) {
    rmSync(path, { force: true });
  }

  const child = spawn(HOST, [
    "terminal-session",
    "--control-file", control,
    "--stop-file", stop,
    "--reply-file", reply,
    "--shell", shellPath,
    "--cwd", "/Users/art/dev/talkie",
  ], {
    cwd: ROOT,
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout.on("data", (chunk) => process.stdout.write(chunk));
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));

  for (let i = 0; i < 40; i += 1) {
    if (existsSync(reply)) break;
    await sleep(100);
  }
  if (!existsSync(reply)) {
    throw new Error(`Terminal session did not write reply file: ${reply}`);
  }
  await sleep(700);
  return { child, control, stop, reply };
}

function appendControl(session, text) {
  writeFileSync(session.control, text, { flag: "a" });
}

async function stopTerminalSession(session) {
  writeFileSync(session.stop, "stop\n");
  await new Promise((resolveClose) => session.child.once("close", resolveClose));
}

function terminalFrame() {
  const response = run([
    "get-window-frame",
    "--bundle-id", ACTION_BUNDLE,
  ], { parseJson: true });
  if (!response?.frame) {
    throw new Error("Unable to resolve Action terminal window frame");
  }
  const topInset = 62;
  return {
    ...response.frame,
    y: response.frame.y + topInset,
    height: response.frame.height - topInset,
  };
}

async function captureTerminal(id, commands) {
  const session = await startTerminalSession(id);
  appendControl(session, "clear\n");
  await sleep(1300);
  const frame = terminalFrame();
  const recording = startRegionRecording(id, frame);
  await sleep(900);
  for (const command of commands) {
    appendControl(session, `${command}\n`);
    await sleep(Math.max(2600, command.length * 58) + 1600);
  }
  await sleep(900);
  const output = await stopRecording(recording);
  await stopTerminalSession(session);
  console.log(`captured ${output}`);
  return output;
}

const outputs = [];

outputs.push({
  id: "talkie-compose-shape-draft",
  title: "Talkie Compose - Shape Draft",
  output: await captureTalkieApp(
    "talkie-compose-shape-draft",
    async () => {
      click(452, 272);
      await sleep(600);
      press("New Note", "AXButton", true);
      await sleep(500);
      setRoleValue("AXTextArea", "");
      await sleep(250);
    },
    [
      async () => {
        setRoleValue(
          "AXTextArea",
          "Messy memo: the preframe queue is good now, but videos need a real completed-treatment shelf. Capture the failing state, trace the render path, and ask Claude Code to patch the Videos tab so done jobs are easy to find."
        );
        await sleep(1400);
      },
      async () => {
        press("gpt-5.4", "AXMenuButton", true);
        await sleep(1600);
      },
      async () => {
        key("Escape", TALKIE_BUNDLE, true);
        await sleep(900);
      },
    ]
  ),
});

outputs.push({
  id: "talkie-search-recovery",
  title: "Talkie Search - Recovery",
  output: await captureTalkieApp(
    "talkie-search-recovery",
    async () => {
      click(452, 198);
      await sleep(700);
      press("Search...", "AXButton", true);
      await sleep(500);
      setRoleValue("AXTextField", "");
      await sleep(250);
    },
    [
      async () => {
        setRoleValue("AXTextField", "codex");
        await sleep(1800);
      },
      async () => {
        key("Down", TALKIE_BUNDLE, true);
        await sleep(500);
        key("Return", TALKIE_BUNDLE, true);
        await sleep(1200);
      },
      async () => {
        key("Escape", TALKIE_BUNDLE, true);
        await sleep(600);
      },
    ]
  ),
});

outputs.push({
  id: "talkie-cli-voice-context",
  title: "Talkie CLI - Voice Context",
  output: await captureTerminal("talkie-cli-voice-context", [
    `talkie search "codex computer use" --json | jq '.[0] | {id,type,app,score,text}'`,
    `talkie memos --since 7d --json | jq '.[0] | {title,text}'`,
  ]),
});

outputs.push({
  id: "talkie-claude-code-handoff",
  title: "Talkie Agentic - Claude Code Handoff",
  output: await captureTerminal("talkie-claude-code-handoff", [
    `talkie search "video tab completed treatment" --json | jq '.[0].context'`,
    `claude "Use the Talkie memo context to patch the Videos tab state."`,
    `talkie workflows --status completed --json | jq '.[] | {workflowName,status,output}'`,
  ]),
});

const manifestPath = resolve(OUT_DIR, "talkie-website-plates.json");
writeFileSync(
  manifestPath,
  `${JSON.stringify({
    capturedAt: new Date().toISOString(),
    outputs,
  }, null, 2)}\n`
);
console.log(`manifest ${manifestPath}`);
