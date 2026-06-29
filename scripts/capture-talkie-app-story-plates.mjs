#!/usr/bin/env node
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const HOST = resolve(ROOT, "native/dist/Action.app/Contents/MacOS/Action");
const OUT_DIR = resolve(ROOT, "artifacts/action-demos");
const DEFAULT_TALKIE_BUNDLE_ID = "to.talkie.app.mac.dev";
const REMOVED_TALKIE_CORE_BUNDLE_ID = ["jdi", "talkie", "core"].join(".");
const FORBIDDEN_BUNDLE_IDS = new Set([REMOVED_TALKIE_CORE_BUNDLE_ID]);
const BUNDLE_ID = process.env.TALKIE_BUNDLE_ID ?? DEFAULT_TALKIE_BUNDLE_ID;

if (FORBIDDEN_BUNDLE_IDS.has(BUNDLE_ID)) {
  throw new Error(`Refusing to target removed Talkie bundle id: ${BUNDLE_ID}`);
}

const sleep = (ms) => new Promise((resolveSleep) => setTimeout(resolveSleep, ms));

function run(args, { allowFailure = false } = {}) {
  try {
    return execFileSync(HOST, args, {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    if (allowFailure) return "";
    throw error;
  }
}

function click(x, y) {
  run(["click-point", "--x", String(x), "--y", String(y)]);
}

function key(keyName, allowFailure = false) {
  run([
    "press-app-key",
    "--bundle-id", BUNDLE_ID,
    "--key", keyName,
  ], { allowFailure });
}

function press(label, role = "AXButton", allowFailure = false) {
  run([
    "press-accessibility-element",
    "--bundle-id", BUNDLE_ID,
    "--label", label,
    "--role", role,
  ], { allowFailure });
}

function setRoleValue(role, value, allowFailure = false) {
  run([
    "set-accessibility-role-value",
    "--bundle-id", BUNDLE_ID,
    "--role", role,
    "--value", value,
  ], { allowFailure });
}

async function prepareWindow() {
  run(["get-window-frame", "--bundle-id", BUNDLE_ID]);
  run(["activate-app", "--bundle-id", BUNDLE_ID], { allowFailure: true });
  await sleep(250);
  run([
    "set-window-frame",
    "--bundle-id", BUNDLE_ID,
    "--x", "420",
    "--y", "96",
    "--width", "1320",
    "--height", "1180",
  ], { allowFailure: true });
  await sleep(450);
  press("Cancel", "AXButton", true);
  press("Close", "AXButton", true);
  key("Escape", true);
  await sleep(250);
}

async function goHome() {
  click(452, 270);
  await sleep(450);
  click(452, 198);
  await sleep(700);
}

function startRecording(id) {
  mkdirSync(OUT_DIR, { recursive: true });
  const output = resolve(OUT_DIR, `${id}.mov`);
  const stop = `${output}.stop`;
  const finished = `${output}.finished`;
  const log = `${output}.log`;
  for (const path of [output, stop, finished, log]) {
    rmSync(path, { force: true });
  }

  const child = spawn(HOST, [
    "record-app-window",
    "--bundle-id", BUNDLE_ID,
    "--fps", "30",
    "--output", output,
    "--stop-file", stop,
    "--finished-file", finished,
    "--debug-log", log,
    "--scale", "1",
  ], {
    cwd: ROOT,
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout.on("data", (chunk) => process.stdout.write(chunk));
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));
  return { child, output, stop, finished };
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

async function capture(id, setup, steps) {
  await prepareWindow();
  await setup();
  const recording = startRecording(id);
  await sleep(1000);
  for (const step of steps) {
    await step();
  }
  await sleep(700);
  const output = await stopRecording(recording);
  console.log(`captured ${output}`);
  return output;
}

const outputs = [];

outputs.push({
  id: "talkie-app-home-to-agent-console",
  title: "Talkie App - Home To Agent Console",
  output: await capture(
    "talkie-app-home-to-agent-console",
    async () => {
      await goHome();
    },
    [
      async () => {
        click(1510, 920);
        await sleep(1800);
      },
    ]
  ),
});

outputs.push({
  id: "talkie-app-compose-model-routing",
  title: "Talkie App - Compose Model Routing",
  output: await capture(
    "talkie-app-compose-model-routing",
    async () => {
      click(452, 270);
      await sleep(700);
      press("New Note", "AXButton", true);
      await sleep(450);
      setRoleValue("AXTextArea", "");
      await sleep(250);
    },
    [
      async () => {
        setRoleValue(
          "AXTextArea",
          "Memo: turn the queue problem into an agent task. Keep the original thought, compare a concise pass, then route the transcript to Claude Code with the current project context."
        );
        await sleep(1100);
      },
      async () => {
        press("gpt-5.4", "AXMenuButton", true);
        await sleep(1700);
      },
      async () => {
        key("Escape", true);
        await sleep(800);
      },
    ]
  ),
});

outputs.push({
  id: "talkie-app-search-recovery",
  title: "Talkie App - Search Recovery",
  output: await capture(
    "talkie-app-search-recovery",
    async () => {
      await goHome();
      press("Search...", "AXButton", true);
      await sleep(450);
      setRoleValue("AXTextField", "", true);
      await sleep(250);
    },
    [
      async () => {
        setRoleValue("AXTextField", "codex");
        await sleep(1800);
      },
      async () => {
        key("Down", true);
        await sleep(400);
        key("Return", true);
        await sleep(1200);
      },
      async () => {
        key("Escape", true);
        await sleep(600);
      },
    ]
  ),
});

outputs.push({
  id: "talkie-app-workflow-run-inspect",
  title: "Talkie App - Workflow Run Inspect",
  output: await capture(
    "talkie-app-workflow-run-inspect",
    async () => {
      await goHome();
      press("Workflows", "AXButton", true);
      await sleep(700);
    },
    [
      async () => {
        press("Hey Talkie, 3 steps", "AXButton", true);
        await sleep(700);
      },
      async () => {
        press("RUN", "AXButton", true);
        await sleep(850);
      },
      async () => {
        click(1000, 525);
        await sleep(200);
        run([
          "type-app-text",
          "--bundle-id", BUNDLE_ID,
          "--text", "agent handoff",
          "--delay-ms", "28",
        ], { allowFailure: true });
        await sleep(800);
      },
      async () => {
        press("Cancel", "AXButton", true);
        await sleep(650);
      },
      async () => {
        press("VIEW", "AXButton", true);
        await sleep(900);
      },
      async () => {
        click(1288, 336);
        await sleep(450);
        click(1212, 336);
        await sleep(500);
      },
      async () => {
        press("Close", "AXButton", true);
        await sleep(650);
      },
    ]
  ),
});

const manifestPath = resolve(OUT_DIR, "talkie-app-story-plates.json");
writeFileSync(
  manifestPath,
  `${JSON.stringify({
    capturedAt: new Date().toISOString(),
    bundleId: BUNDLE_ID,
    outputs,
  }, null, 2)}\n`
);
console.log(`manifest ${manifestPath}`);
