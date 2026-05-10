#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(scriptDir, "../../..");

const args = parseArgs(process.argv.slice(2));
const debugPort = args.debugPort ?? "9335";
const profileDir =
  args.profileDir ?? `${homedir()}/Library/Application Support/Action/ChromeProfiles/mira`;
const chromeAppName = args.chromeAppName ?? "Google Chrome";
const outputPath =
  args.output ??
  `${rootDir}/artifacts/captures/mira-motion-trail-${new Date()
    .toISOString()
    .replaceAll(/[-:]/g, "")
    .replace(/\..+$/, "")
    .replace("T", "-")}/trail-report.json`;

const pid = await ensureMiraChrome({
  chromeAppName,
  profileDir,
  debugPort,
  shouldStart: args.start !== false,
});
await activatePid(pid);
const frame = await readLargestWindowFrame(pid);
const plan = buildTrailPlan(frame);
const report = scorePlan(frame, plan);

if (args.run) {
  await runTrail(plan);
}

await mkdir(dirname(outputPath), { recursive: true });
await Bun.write(outputPath, `${JSON.stringify(report, null, 2)}\n`);
printReport(report, outputPath, args.run);

if (args.failOnNeedsWork && report.verdict !== "good") {
  process.exit(1);
}

function buildTrailPlan(frame) {
  const path = [
    {
      id: "omnibox",
      label: "Omnibox",
      reason: "Mira should introduce the exact browser target before address entry.",
      target: point(frame, 0.42, 0.035),
      zone: rect(frame, 0.255, 0.018, 0.49, 0.036),
      mira: near(frame, 0.42, 0.035, 180, 128),
      durationMs: 520,
    },
    {
      id: "google-search",
      label: "Google search",
      reason: "Mira should stay near the search field without covering typed text.",
      target: point(frame, 0.5, 0.37),
      zone: rect(frame, 0.3, 0.335, 0.4, 0.07),
      mira: near(frame, 0.5, 0.37, 165, -150),
      durationMs: 980,
    },
    {
      id: "omnibox-return",
      label: "Omnibox return",
      reason: "Mira should visibly hand the story back to navigation.",
      target: point(frame, 0.42, 0.035),
      zone: rect(frame, 0.255, 0.018, 0.49, 0.036),
      mira: near(frame, 0.42, 0.035, 180, 128),
      durationMs: 900,
    },
    {
      id: "midjourney-prompt",
      label: "Midjourney prompt",
      reason: "Mira should land near the prompt rail, not in the middle of the canvas.",
      target: point(frame, 0.48, 0.092),
      zone: rect(frame, 0.13, 0.055, 0.68, 0.052),
      mira: near(frame, 0.48, 0.092, 180, 126),
      durationMs: 760,
    },
    {
      id: "inspection-rail",
      label: "Inspection rail",
      reason: "Mira should point at the browser/trace context without masking the generated image.",
      target: point(frame, 0.77, 0.25),
      zone: rect(frame, 0.78, 0.09, 0.18, 0.52),
      mira: near(frame, 0.77, 0.25, -230, 78),
      durationMs: 940,
    },
    {
      id: "artifact-beat",
      label: "Artifact beat",
      reason: "Mira should finish near the trace/artifact story, still above the lower canvas.",
      target: point(frame, 0.79, 0.16),
      zone: rect(frame, 0.76, 0.08, 0.2, 0.28),
      mira: near(frame, 0.79, 0.16, -220, 82),
      durationMs: 680,
    },
  ];

  return path.map((step, index) => ({
    ...step,
    previousMira: index > 0 ? path[index - 1].mira : null,
  }));
}

function scorePlan(frame, plan) {
  const actorSize = Number(args.actorSize ?? 170);
  const idealMin = Number(args.idealMin ?? 130);
  const idealMax = Number(args.idealMax ?? 290);
  const farMax = Number(args.farMax ?? 380);
  const maxSegment = Number(args.maxSegment ?? 620);
  const steps = [];
  const issues = [];
  let score = 100;

  for (const step of plan) {
    const distance = dist(step.target, step.mira);
    const segmentDistance = step.previousMira ? dist(step.previousMira, step.mira) : 0;
    const actorRect = rectFromCenter(step.mira, actorSize, actorSize);
    const overlapRatio = overlapArea(actorRect, step.zone) / rectArea(step.zone);
    const yBand = (step.mira.y - frame.y) / frame.height;
    const notes = [];
    let grade = "good";

    if (distance < 90) {
      grade = "bad";
      score -= 18;
      notes.push("too close to the target; reads as blocking rather than guiding");
    } else if (distance < idealMin) {
      grade = "watch";
      score -= 6;
      notes.push("a little tight to the action");
    } else if (distance > farMax) {
      grade = "bad";
      score -= 18;
      notes.push("too far from the action to explain the control lane");
    } else if (distance > idealMax) {
      grade = "watch";
      score -= 7;
      notes.push("slightly detached from the target");
    }

    if (overlapRatio > 0.12) {
      grade = "bad";
      score -= 22;
      notes.push(`likely occludes the target zone (${Math.round(overlapRatio * 100)}% overlap)`);
    } else if (overlapRatio > 0.03) {
      if (grade === "good") grade = "watch";
      score -= 8;
      notes.push(`minor target overlap (${Math.round(overlapRatio * 100)}%)`);
    }

    if (yBand > 0.55) {
      grade = "bad";
      score -= 12;
      notes.push("falls into the lower half where the main visual content lives");
    } else if (yBand > 0.47) {
      if (grade === "good") grade = "watch";
      score -= 5;
      notes.push("close to the lower content band");
    }

    if (segmentDistance > maxSegment) {
      if (grade === "good") grade = "watch";
      score -= 8;
      notes.push("large jump between beats");
    }

    if (notes.length === 0) {
      notes.push("near the action without covering it");
    }

    const scoredStep = {
      id: step.id,
      label: step.label,
      grade,
      reason: step.reason,
      target: roundPoint(step.target),
      mira: roundPoint(step.mira),
      durationMs: step.durationMs,
      targetDistancePx: Math.round(distance),
      segmentDistancePx: Math.round(segmentDistance),
      targetOverlapPercent: Math.round(overlapRatio * 100),
      verticalBand: Number(yBand.toFixed(2)),
      notes,
    };
    steps.push(scoredStep);

    if (grade !== "good") {
      issues.push(`${step.label}: ${notes.join("; ")}`);
    }
  }

  score = Math.max(0, Math.round(score));
  const verdict = score >= 86 && issues.length === 0 ? "good" : score >= 72 ? "needs-tuning" : "bad";

  return {
    verdict,
    score,
    generatedAt: new Date().toISOString(),
    frame: roundRect(frame),
    assumptions: {
      actorFootprintPx: actorSize,
      idealDistancePx: [idealMin, idealMax],
      farDistancePx: farMax,
      maxSegmentPx: maxSegment,
      occlusionModel: "actor footprint is treated as a centered square around the requested move point",
    },
    issues,
    steps,
  };
}

async function runTrail(plan) {
  await callOverlay(["show", "--no-message"]);
  await callOverlay(["move", String(plan[0].mira.x), String(plan[0].mira.y), "240"]);
  await sleep(220);

  for (const step of plan) {
    console.log(
      `[motion] ${step.label} -> ${Math.round(step.mira.x)},${Math.round(step.mira.y)} (${step.durationMs}ms)`
    );
    await callOverlay([
      "move",
      String(Math.round(step.mira.x)),
      String(Math.round(step.mira.y)),
      String(step.durationMs),
    ]);
    await sleep(step.durationMs * 0.82);
  }
  await sleep(250);
}

async function ensureMiraChrome({ chromeAppName, profileDir, debugPort, shouldStart }) {
  let pid = await miraPid();
  if (pid || !shouldStart) {
    if (!pid) {
      throw new Error("Mira Chrome profile is not running.");
    }
    return pid;
  }

  await run("open", [
    "-n",
    "-a",
    chromeAppName,
    "--args",
    `--user-data-dir=${profileDir}`,
    "--no-first-run",
    "--no-default-browser-check",
    `--remote-debugging-port=${debugPort}`,
    "--new-window",
    "about:blank",
  ]);
  await sleep(2200);
  pid = await miraPid();
  if (!pid) {
    throw new Error("Unable to start Mira Chrome profile.");
  }
  return pid;
}

async function miraPid() {
  const result = await run("pgrep", [
    "-f",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir=.*ChromeProfiles/mira",
  ], { allowFailure: true });
  return result.stdout
    .trim()
    .split(/\s+/)
    .filter(Boolean)[0] ?? null;
}

async function activatePid(pid) {
  await run("osascript", [
    "-",
    String(pid),
  ], {
    stdin: `use framework "AppKit"
use scripting additions
on run argv
  set targetPid to (item 1 of argv) as integer
  set appRef to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:targetPid
  if appRef is not missing value then
    appRef's activateWithOptions:(current application's NSApplicationActivateIgnoringOtherApps)
  end if
end run
`,
  });
  await sleep(250);
}

async function readLargestWindowFrame(pid) {
  const swift = `import CoreGraphics
import Foundation

let pid = Int(ProcessInfo.processInfo.environment["MIRA_PID"] ?? "") ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let matches = windows.compactMap { item -> (Double, [String: Any])? in
    guard (item[kCGWindowOwnerPID as String] as? Int) == pid,
          (item[kCGWindowLayer as String] as? Int ?? 0) == 0,
          let bounds = item[kCGWindowBounds as String] as? [String: Any] else { return nil }
    let width = bounds["Width"] as? Double ?? 0
    let height = bounds["Height"] as? Double ?? 0
    guard width > 400, height > 300 else { return nil }
    return (width * height, bounds)
}.sorted { $0.0 > $1.0 }

guard let bounds = matches.first?.1 else {
    fputs("Unable to resolve Mira Chrome window frame.\\n", stderr)
    exit(1)
}
let payload: [String: Any] = [
    "x": bounds["X"] ?? 0,
    "y": bounds["Y"] ?? 0,
    "width": bounds["Width"] ?? 0,
    "height": bounds["Height"] ?? 0,
]
let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
`;
  const result = await run("swift", ["-"], {
    stdin: swift,
    env: { MIRA_PID: String(pid) },
  });
  const raw = JSON.parse(result.stdout);
  return {
    x: Number(raw.x),
    y: Number(raw.y),
    width: Number(raw.width),
    height: Number(raw.height),
  };
}

async function callOverlay(args) {
  await run("bun", [`${rootDir}/scripts/mira-overlay.mjs`, ...args], {
    cwd: rootDir,
  });
}

function point(frame, rx, ry) {
  return {
    x: frame.x + frame.width * rx,
    y: frame.y + frame.height * ry,
  };
}

function rect(frame, rx, ry, rw, rh) {
  return {
    x: frame.x + frame.width * rx,
    y: frame.y + frame.height * ry,
    width: frame.width * rw,
    height: frame.height * rh,
  };
}

function near(frame, rx, ry, dx, dy) {
  const target = point(frame, rx, ry);
  const side = target.x + dx > frame.x + frame.width - 190 ? -235 : dx;
  return {
    x: clamp(target.x + side, frame.x + 110, frame.x + frame.width - 115),
    y: clamp(target.y + dy, frame.y + 94, frame.y + frame.height - 150),
  };
}

function rectFromCenter(center, width, height) {
  return {
    x: center.x - width / 2,
    y: center.y - height / 2,
    width,
    height,
  };
}

function overlapArea(a, b) {
  const x = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
  const y = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
  return x * y;
}

function rectArea(rectangle) {
  return rectangle.width * rectangle.height;
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function roundPoint(point) {
  return {
    x: Math.round(point.x),
    y: Math.round(point.y),
  };
}

function roundRect(rectangle) {
  return {
    x: Math.round(rectangle.x),
    y: Math.round(rectangle.y),
    width: Math.round(rectangle.width),
    height: Math.round(rectangle.height),
  };
}

function printReport(report, outputPath, didRun) {
  const adjective =
    report.verdict === "good" ? "good" : report.verdict === "needs-tuning" ? "needs tuning" : "bad";
  console.log(`[trail] verdict=${adjective} score=${report.score}`);
  for (const step of report.steps) {
    const notes = step.notes.join("; ");
    console.log(
      `[trail] ${step.grade.padEnd(5)} ${step.label.padEnd(18)} distance=${String(
        step.targetDistancePx
      ).padStart(3)}px overlap=${String(step.targetOverlapPercent).padStart(2)}% yBand=${
        step.verticalBand
      } :: ${notes}`
    );
  }
  if (report.issues.length > 0) {
    console.log("[trail] issues:");
    for (const issue of report.issues) {
      console.log(`  - ${issue}`);
    }
  }
  console.log(`[trail] report=${outputPath}`);
  if (didRun) {
    console.log("[trail] motion-only run complete; no recording, typing, rendering, or submit ran.");
  }
}

function parseArgs(rawArgs) {
  const parsed = {
    run: false,
    start: true,
    failOnNeedsWork: false,
  };
  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    if (arg === "--run") {
      parsed.run = true;
    } else if (arg === "--no-start") {
      parsed.start = false;
    } else if (arg === "--fail-on-needs-work") {
      parsed.failOnNeedsWork = true;
    } else if (arg === "--output") {
      parsed.output = rawArgs[++index];
    } else if (arg === "--debug-port") {
      parsed.debugPort = rawArgs[++index];
    } else if (arg === "--profile-dir") {
      parsed.profileDir = rawArgs[++index];
    } else if (arg === "--chrome-app") {
      parsed.chromeAppName = rawArgs[++index];
    } else if (arg === "--actor-size") {
      parsed.actorSize = rawArgs[++index];
    } else if (arg === "--ideal-min") {
      parsed.idealMin = rawArgs[++index];
    } else if (arg === "--ideal-max") {
      parsed.idealMax = rawArgs[++index];
    } else if (arg === "--far-max") {
      parsed.farMax = rawArgs[++index];
    } else if (arg === "--max-segment") {
      parsed.maxSegment = rawArgs[++index];
    } else if (arg === "--help" || arg === "-h") {
      printUsageAndExit();
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return parsed;
}

function printUsageAndExit() {
  console.log(
    [
      "Usage: bun native/engine/scripts/check-mira-motion-trail.mjs [options]",
      "",
      "Options:",
      "  --run                    Move Mira through the checked trail",
      "  --output <path>          Write JSON report to this path",
      "  --no-start               Require an already running Mira Chrome profile",
      "  --actor-size <px>        Assumed centered Mira footprint for occlusion checks",
      "  --fail-on-needs-work     Exit non-zero unless the verdict is good",
    ].join("\n")
  );
  process.exit(0);
}

async function run(command, commandArgs, options = {}) {
  const proc = Bun.spawn([command, ...commandArgs], {
    cwd: options.cwd,
    env: { ...process.env, ...(options.env ?? {}) },
    stdin: options.stdin ? "pipe" : undefined,
    stdout: "pipe",
    stderr: "pipe",
  });
  if (options.stdin) {
    proc.stdin.write(options.stdin);
    proc.stdin.end();
  }
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (exitCode !== 0 && !options.allowFailure) {
    throw new Error(`${command} ${commandArgs.join(" ")} failed (${exitCode}): ${stderr || stdout}`);
  }
  return { stdout, stderr, exitCode };
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}
