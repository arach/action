#!/usr/bin/env node
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

function press(label, role = "AXButton", allowFailure = false) {
  run([
    "press-accessibility-element",
    "--bundle-id", BUNDLE_ID,
    "--label", label,
    "--role", role,
  ], { allowFailure });
}

function click(x, y) {
  run(["click-point", "--x", String(x), "--y", String(y)]);
}

function type(text, delayMs = 28) {
  run([
    "type-app-text",
    "--bundle-id", BUNDLE_ID,
    "--text", text,
    "--delay-ms", String(delayMs),
  ]);
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
  await sleep(300);
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

  return { child, output, stop, finished, log };
}

async function stopRecording(recording) {
  writeFileSync(recording.stop, "stop\n");
  const exitCode = await new Promise((resolve, reject) => {
    recording.child.once("error", reject);
    recording.child.once("close", resolve);
  });
  if (exitCode !== 0) {
    throw new Error(`Recording process exited with ${exitCode}`);
  }
  if (!existsSync(recording.finished)) {
    throw new Error(`Missing finished marker: ${recording.finished}`);
  }
  return recording.output;
}

async function capture(id, steps) {
  await prepareWindow();
  const recording = startRecording(id);
  await sleep(1200);
  for (const step of steps) {
    await step();
  }
  await sleep(700);
  const output = await stopRecording(recording);
  console.log(`captured ${output}`);
  return output;
}

const demos = [
  {
    id: "talkie-doing-run-to-visualizer",
    title: "Talkie Doing - Run To Visualizer",
    steps: [
      async () => { press("Hey Talkie, 3 steps"); await sleep(800); },
      async () => { press("RUN"); await sleep(900); },
      async () => { click(1000, 525); await sleep(150); type("standup notes"); await sleep(900); },
      async () => { press("Cancel"); await sleep(650); },
      async () => { press("VIEW"); await sleep(950); },
      async () => { click(1288, 336); await sleep(450); click(1288, 336); await sleep(450); },
      async () => { click(1212, 336); await sleep(550); },
      async () => { press("Close"); await sleep(650); },
    ],
  },
  {
    id: "talkie-doing-switch-and-inspect",
    title: "Talkie Doing - Switch And Inspect",
    steps: [
      async () => { press("Transcribe, 1 step"); await sleep(900); },
      async () => { press("VIEW"); await sleep(950); },
      async () => { click(1288, 336); await sleep(500); click(1212, 336); await sleep(500); },
      async () => { press("Close"); await sleep(650); },
      async () => { press("Hey Talkie, 3 steps"); await sleep(850); },
      async () => { press("RUN"); await sleep(850); },
      async () => { click(1000, 525); await sleep(150); type("capture"); await sleep(850); },
      async () => { press("Cancel"); await sleep(600); },
    ],
  },
];

const outputs = [];
for (const demo of demos) {
  outputs.push({
    ...demo,
    output: await capture(demo.id, demo.steps),
  });
}

const manifestPath = resolve(OUT_DIR, "talkie-doing-demos.json");
writeFileSync(
  manifestPath,
  `${JSON.stringify({
    capturedAt: new Date().toISOString(),
    bundleId: BUNDLE_ID,
    outputs: outputs.map(({ id, title, output }) => ({ id, title, output })),
  }, null, 2)}\n`,
);
console.log(`manifest ${manifestPath}`);
