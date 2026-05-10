#!/usr/bin/env bun

import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const args = parseArgs(process.argv.slice(2));
const videoPath = resolve(args.video || "");
if (!videoPath || !existsSync(videoPath)) {
  throw new Error("Missing --video <path>");
}

const rootDir = resolve(new URL("../../..", import.meta.url).pathname);
const hyperframes = args.hyperframes || process.env.HYPERFRAMES_BIN || "/Users/art/.local/bin/hyperframes";
const ffmpeg = process.env.FFMPEG_BIN || "ffmpeg";
const ffprobe = process.env.FFPROBE_BIN || "ffprobe";
const outputPath = resolve(args.output || join(dirname(videoPath), "action-mira-polished-demo-composed.mp4"));
const workDir = resolve(args.workDir || join(dirname(videoPath), "hyperframes"));
const assetsDir = join(workDir, "assets");
const duration = Math.max(12, Math.ceil(Number(args.duration || probeDuration(videoPath)) * 10) / 10);
const posterPath = args.poster
  ? resolve(args.poster)
  : defaultPosterPath(rootDir);
const narrationPath = join(assetsDir, "narration.wav");
const narrationScriptPath = join(workDir, "narration.txt");
const audioCuesPath = args.audioCues
  ? resolve(args.audioCues)
  : join(dirname(videoPath), "audio-cues.jsonl");
const foleyPath = join(assetsDir, "foley.wav");

mkdirSync(assetsDir, { recursive: true });
writeFileSync(narrationScriptPath, `${narrationText()}\n`);
transcodeSourceVideo(videoPath, join(assetsDir, "source.mp4"));
const foleyCueCount = existsSync(audioCuesPath)
  ? renderFoleyTrack({ cuePath: audioCuesPath, outputPath: foleyPath, duration })
  : 0;

if (posterPath && existsSync(posterPath)) {
  copyFileSync(posterPath, join(assetsDir, "logo-direction.png"));
}

if (args.tts !== "0") {
  renderNarration({
    hyperframes,
    narrationPath,
    scriptPath: narrationScriptPath,
    voice: args.voice || process.env.ACTION_MIRA_HYPERFRAMES_TTS_VOICE || "af_nova",
    speed: args.speed || process.env.ACTION_MIRA_HYPERFRAMES_TTS_SPEED || "1.03",
  });
}

writeProjectFiles({
  workDir,
  duration,
  posterPath,
  hasNarration: existsSync(narrationPath),
  hasFoley: foleyCueCount > 0,
});

const render = spawnSync(hyperframes, [
  "render",
  workDir,
  "--output", outputPath,
  "--fps", args.fps || "30",
  "--quality", args.quality || "high",
  "--workers", args.workers || "2",
], { stdio: "inherit" });

if (render.status !== 0) {
  process.exit(render.status ?? 1);
}

console.log(JSON.stringify({
  status: "rendered",
  outputPath,
  workDir,
  duration,
}, null, 2));

function writeProjectFiles({ workDir, duration, posterPath, hasNarration, hasFoley }) {
  writeFileSync(join(workDir, "hyperframes.json"), `${JSON.stringify({
    $schema: "https://hyperframes.heygen.com/schema/hyperframes.json",
    paths: {
      blocks: "compositions",
      components: "compositions/components",
      assets: "assets",
    },
  }, null, 2)}\n`);

  writeFileSync(join(workDir, "meta.json"), `${JSON.stringify({
    id: "action-mira-polished-demo",
    name: "Action Mira polished demo",
  }, null, 2)}\n`);

  writeFileSync(join(workDir, "index.html"), html({
    duration,
    hasPoster: Boolean(posterPath && existsSync(posterPath)),
    hasNarration,
    hasFoley,
  }));
}

function transcodeSourceVideo(inputPath, outputPath) {
  const result = spawnSync(ffmpeg, [
    "-y",
    "-i", inputPath,
    "-an",
    "-vf", "scale=1220:-2:flags=lanczos",
    "-r", "30",
    "-c:v", "libx264",
    "-profile:v", "high",
    "-pix_fmt", "yuv420p",
    "-g", "30",
    "-keyint_min", "30",
    "-sc_threshold", "0",
    "-crf", "18",
    "-preset", "medium",
    "-movflags", "+faststart",
    outputPath,
  ], { stdio: "inherit" });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function renderNarration({ hyperframes, narrationPath, scriptPath, voice, speed }) {
  const rendered = spawnSync(hyperframes, [
    "tts",
    scriptPath,
    "--output", narrationPath,
    "--voice", voice,
    "--speed", speed,
  ], { stdio: "inherit" });

  if (rendered.status === 0) {
    return;
  }

  const aiffPath = narrationPath.replace(/\.wav$/i, ".aiff");
  const say = spawnSync("/usr/bin/say", [
    "-v", "Samantha",
    "-r", "178",
    "-f", scriptPath,
    "-o", aiffPath,
  ], { stdio: "inherit" });
  if (say.status !== 0) {
    console.error("[warn] Narration failed; rendering silent composition.");
    return;
  }

  const convert = spawnSync(ffmpeg, ["-y", "-i", aiffPath, narrationPath], { stdio: "inherit" });
  if (convert.status !== 0) {
    console.error("[warn] Narration conversion failed; rendering silent composition.");
  }
}

function renderFoleyTrack({ cuePath, outputPath, duration }) {
  const cues = readFileSync(cuePath, "utf8")
    .split(/\n+/)
    .filter(Boolean)
    .map((line) => JSON.parse(line))
    .filter((cue) => Number.isFinite(cue.atMs) && Number.isFinite(cue.durationMs));
  if (cues.length === 0) {
    return 0;
  }

  const sampleRate = 48000;
  const totalSamples = Math.ceil((duration + 0.5) * sampleRate);
  const samples = new Float32Array(totalSamples);
  let seed = 0x4d495241;
  const random = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 0xffffffff;
  };

  const addTick = (timeSeconds, frequency, gain = 0.32) => {
    const start = Math.max(0, Math.round(timeSeconds * sampleRate));
    const length = Math.round(0.038 * sampleRate);
    for (let index = 0; index < length && start + index < samples.length; index += 1) {
      const t = index / sampleRate;
      const envelope = Math.exp(-t * 82);
      const tone = Math.sin(2 * Math.PI * frequency * t) * 0.62
        + Math.sin(2 * Math.PI * (frequency * 1.74) * t) * 0.18
        + (random() - 0.5) * 0.32;
      samples[start + index] += tone * envelope * gain;
    }
  };

  for (const cue of cues) {
    const at = cue.atMs / 1000;
    const durationSeconds = Math.max(0.2, cue.durationMs / 1000);
    if (cue.kind === "typing") {
      const start = at + 0.08;
      const end = at + durationSeconds * 0.92;
      const interval = durationSeconds > 2.4 ? 0.068 : 0.082;
      let count = 0;
      for (let t = start; t < end; t += interval) {
        addTick(t, count % 3 === 0 ? 1280 : count % 3 === 1 ? 1540 : 1760, 0.23);
        count += 1;
      }
    } else if (cue.kind === "key") {
      addTick(at + durationSeconds * 0.42, 760, 0.42);
    }
  }

  let peak = 0;
  for (const sample of samples) {
    peak = Math.max(peak, Math.abs(sample));
  }
  const normalize = peak > 0.82 ? 0.82 / peak : 1;
  writeWav(outputPath, samples, sampleRate, normalize);
  return cues.length;
}

function writeWav(outputPath, samples, sampleRate, gain) {
  const dataSize = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataSize, 40);
  for (let index = 0; index < samples.length; index += 1) {
    const value = Math.max(-1, Math.min(1, samples[index] * gain));
    buffer.writeInt16LE(Math.round(value * 32767), 44 + index * 2);
  }
  writeFileSync(outputPath, buffer);
}

function probeDuration(path) {
  const raw = execFileSync(ffprobe, [
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1",
    path,
  ], { encoding: "utf8" }).trim();
  const duration = Number(raw);
  if (!Number.isFinite(duration) || duration <= 0) {
    throw new Error(`Unable to resolve video duration for ${path}`);
  }
  return duration;
}

function defaultPosterPath(rootDir) {
  const candidates = [
    join(rootDir, "docs/assets/action-mira-logo-poster.png"),
    "/Users/art/Library/Application Support/Talkie/Tray/screenshots/Talkie Capture - 2026-05-09 15.30.46 - Window - 1280x1049 - 241533aa.png",
  ];
  return candidates.find((candidate) => existsSync(candidate));
}

function narrationText() {
  return [
    "Mira is driving a real Chrome profile while Action records the exact macOS window.",
    "The cursor is the teaching layer. The control lanes are vision, accessibility, browser context, and native input.",
    "Mira can look with a vision model, resolve targets with AX or page context, then act through a precise local channel.",
    "The visible typing is there for dramatic education. The trace records how each action was actually delivered.",
    "Midjourney is the visual payoff, but the product is the reliable loop: observe, resolve, act, inspect, and save artifacts.",
  ].join(" ");
}

function html({ duration, hasPoster, hasNarration, hasFoley }) {
  const chapters = [
    { at: 0.25, dur: 4.55, title: "Record", detail: "exact Mira Chrome region" },
    { at: 5.0, dur: 6.4, title: "Look", detail: "VLM and browser observation" },
    { at: 11.7, dur: 5.6, title: "Resolve", detail: "AX, DOM, or CDP targets" },
    { at: 17.6, dur: 6.1, title: "Act", detail: "native input channel" },
    { at: 24.0, dur: 6.7, title: "Teach", detail: "cursor and typing are visible cues" },
    { at: 31.0, dur: Math.max(4.2, duration - 31.0), title: "Artifact", detail: "video, trace, marker" },
  ];
  const caption = (item, index) => `
        <div id="caption-${index + 1}" class="caption clip" data-start="${item.at}" data-duration="${item.dur}" data-track-index="8">
          <span>${escapeHtml(item.title)}</span>${escapeHtml(item.detail)}
        </div>`;
  const chip = (item, index) => `
          <div id="chapter-${index + 1}" class="chapter-chip clip" data-start="${item.at}" data-duration="${item.dur}" data-track-index="${12 + index}">
            <span>${String(index + 1).padStart(2, "0")}</span>
            <strong>${escapeHtml(item.title)}</strong>
            ${escapeHtml(item.detail)}
          </div>`;

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1920, height=1080" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>
      * { box-sizing: border-box; }
      html, body {
        margin: 0;
        width: 1920px;
        height: 1080px;
        overflow: hidden;
        background: #ebe6d7;
        color: #193235;
        font-family: Inter, Arial, sans-serif;
      }
      #root {
        position: relative;
        width: 1920px;
        height: 1080px;
        overflow: hidden;
        background:
          linear-gradient(90deg, rgba(25, 50, 53, 0.05) 1px, transparent 1px),
          linear-gradient(0deg, rgba(25, 50, 53, 0.05) 1px, transparent 1px),
          #ebe6d7;
        background-size: 48px 48px, 48px 48px, auto;
      }
      .grain {
        position: absolute;
        inset: 0;
        background-image: radial-gradient(rgba(25, 50, 53, 0.08) 0.6px, transparent 0.8px);
        background-size: 5px 5px;
        opacity: 0.35;
        pointer-events: none;
      }
      .stage {
        position: absolute;
        left: 68px;
        top: 62px;
        width: 1256px;
        height: 956px;
      }
      .window-shell {
        position: absolute;
        inset: 0;
        border: 2px solid #193235;
        background: #101412;
        box-shadow: 18px 24px 0 rgba(25, 50, 53, 0.14);
        overflow: hidden;
      }
      .window-bar {
        height: 42px;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 0 18px;
        border-bottom: 1px solid rgba(235, 230, 215, 0.16);
        background: #171c1a;
      }
      .dot { width: 13px; height: 13px; border-radius: 50%; background: #ff725e; }
      .dot:nth-child(2) { background: #e5b84d; }
      .dot:nth-child(3) { background: #12b6c6; }
      .bar-title {
        margin-left: auto;
        color: rgba(235, 230, 215, 0.74);
        font-family: "JetBrains Mono", "Courier New", monospace;
        font-size: 16px;
      }
      video.source {
        position: absolute;
        left: 16px;
        right: 16px;
        top: 58px;
        bottom: 16px;
        width: calc(100% - 32px);
        height: calc(100% - 74px);
        object-fit: contain;
        background: #070908;
      }
      .scan-corners::before,
      .scan-corners::after,
      .corner-a,
      .corner-b {
        content: "";
        position: absolute;
        width: 56px;
        height: 56px;
        border-color: #12b6c6;
        opacity: 0.86;
      }
      .scan-corners::before { left: 34px; top: 76px; border-left: 4px solid; border-top: 4px solid; }
      .scan-corners::after { right: 34px; top: 76px; border-right: 4px solid; border-top: 4px solid; }
      .corner-a { left: 34px; bottom: 34px; border-left: 4px solid; border-bottom: 4px solid; }
      .corner-b { right: 34px; bottom: 34px; border-right: 4px solid; border-bottom: 4px solid; }
      .rail {
        position: absolute;
        left: 1370px;
        top: 78px;
        width: 466px;
        height: 922px;
        display: flex;
        flex-direction: column;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 14px;
        font-family: "JetBrains Mono", "Courier New", monospace;
        font-size: 18px;
        letter-spacing: 0.03em;
        text-transform: uppercase;
      }
      .mark {
        position: relative;
        width: 56px;
        height: 56px;
      }
      .mark::before {
        content: "A";
        position: absolute;
        inset: 0;
        color: #193235;
        font-size: 58px;
        font-weight: 900;
        line-height: 48px;
      }
      .mark::after {
        content: "";
        position: absolute;
        right: 6px;
        bottom: 4px;
        width: 13px;
        height: 13px;
        border-radius: 50%;
        background: #ff725e;
        box-shadow: -22px -21px 0 #12b6c6;
      }
      h1 {
        margin: 54px 0 0;
        font-size: 76px;
        line-height: 0.93;
        letter-spacing: 0;
        max-width: 420px;
      }
      .sub {
        margin-top: 28px;
        color: rgba(25, 50, 53, 0.75);
        font-size: 25px;
        line-height: 1.23;
        max-width: 390px;
      }
      .chapters {
        position: relative;
        margin-top: 46px;
        height: 262px;
      }
      .chapter-chip {
        position: absolute;
        inset: 0 auto auto 0;
        width: 436px;
        min-height: 86px;
        padding: 18px 20px 18px 82px;
        background: #193235;
        color: #ebe6d7;
        border-radius: 4px;
        font-size: 20px;
        line-height: 1.22;
        box-shadow: 10px 10px 0 rgba(255, 114, 94, 0.24);
      }
      .chapter-chip span {
        position: absolute;
        left: 20px;
        top: 20px;
        font-family: "JetBrains Mono", "Courier New", monospace;
        color: #12b6c6;
        font-size: 18px;
      }
      .chapter-chip strong {
        display: block;
        color: #ffffff;
        font-size: 25px;
        margin-bottom: 3px;
      }
      .artifact-list {
        margin-top: auto;
        border-top: 2px solid rgba(25, 50, 53, 0.2);
        padding-top: 25px;
        display: grid;
        gap: 12px;
      }
      .artifact-row {
        display: flex;
        align-items: center;
        gap: 13px;
        font-family: "JetBrains Mono", "Courier New", monospace;
        font-size: 19px;
        color: rgba(25, 50, 53, 0.78);
      }
      .artifact-row::before {
        content: "";
        width: 12px;
        height: 12px;
        background: #12b6c6;
      }
      .artifact-row:nth-child(2)::before { background: #ff725e; border-radius: 50%; }
      .artifact-row:nth-child(3)::before { background: #193235; }
      .logo-card {
        position: absolute;
        right: 64px;
        bottom: 42px;
        width: 206px;
        height: 238px;
        border: 2px solid #193235;
        background: #f1eddf;
        overflow: hidden;
        box-shadow: 10px 10px 0 rgba(25, 50, 53, 0.14);
      }
      .logo-card img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .logo-card .fallback {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        font-size: 110px;
        font-weight: 900;
      }
      .caption {
        position: absolute;
        left: 130px;
        bottom: 44px;
        width: 1120px;
        padding: 18px 24px;
        background: rgba(235, 230, 215, 0.94);
        border: 2px solid #193235;
        color: #193235;
        font-size: 25px;
        line-height: 1.18;
        box-shadow: 8px 8px 0 rgba(18, 182, 198, 0.28);
      }
      .caption span {
        display: inline-block;
        margin-right: 18px;
        color: #ff725e;
        font-family: "JetBrains Mono", "Courier New", monospace;
        font-size: 21px;
        text-transform: uppercase;
      }
      .progress {
        position: absolute;
        left: 68px;
        right: 84px;
        bottom: 22px;
        height: 5px;
        background: rgba(25, 50, 53, 0.18);
      }
      .progress div {
        width: 100%;
        height: 100%;
        transform-origin: left center;
        transform: scaleX(0);
        background: linear-gradient(90deg, #12b6c6, #ff725e);
        animation: progress ${duration}s linear forwards;
      }
      @keyframes progress { to { transform: scaleX(1); } }
    </style>
  </head>
  <body>
    <div
      id="root"
      data-composition-id="main"
      data-start="0"
      data-duration="${duration}"
      data-width="1920"
      data-height="1080"
    >
      <div class="grain"></div>
      <div class="stage">
        <div class="window-shell">
          <div class="window-bar">
            <div class="dot"></div>
            <div class="dot"></div>
            <div class="dot"></div>
            <div class="bar-title">Action.app records Mira Chrome · cursor is a teaching layer</div>
          </div>
          <video id="source-video" class="source clip" data-start="0" data-duration="${duration}" data-track-index="1" src="assets/source.mp4" muted autoplay playsinline></video>
          <div class="scan-corners"></div>
          <div class="corner-a"></div>
          <div class="corner-b"></div>
        </div>
      </div>

      <div class="rail">
        <div class="brand"><div class="mark"></div><div>mira / action</div></div>
        <h1>Vision, AX, native input.</h1>
        <div class="sub">A visible run through Google and Midjourney. The cursor teaches; the trace tells the real control path.</div>
        <div class="chapters">
${chapters.map(chip).join("\n")}
        </div>
        <div class="artifact-list">
          <div class="artifact-row">VLM / AX context</div>
          <div class="artifact-row">browser target trace</div>
          <div class="artifact-row">finished marker</div>
        </div>
      </div>

${chapters.map(caption).join("\n")}
      ${hasPoster ? `<div id="logo-direction" class="logo-card clip" data-start="${Math.max(20, duration - 13)}" data-duration="${Math.max(8, duration - Math.max(20, duration - 13))}" data-track-index="7"><img src="assets/logo-direction.png" /></div>` : `<div id="logo-direction" class="logo-card clip" data-start="${Math.max(20, duration - 13)}" data-duration="${Math.max(8, duration - Math.max(20, duration - 13))}" data-track-index="7"><div class="fallback">A</div></div>`}
      ${hasNarration ? `<audio id="narration-audio" class="clip" data-start="0.25" data-duration="${duration}" data-track-index="2" data-volume="1" data-has-audio="true" src="assets/narration.wav"></audio>` : ""}
      ${hasFoley ? `<audio id="foley-audio" class="clip" data-start="0" data-duration="${duration}" data-track-index="3" data-volume="0.88" data-has-audio="true" src="assets/foley.wav"></audio>` : ""}
      <div class="progress"><div></div></div>
    </div>
    <script>
      window.__timelines = window.__timelines || {};
      const tl = gsap.timeline({ paused: true });
      tl.from(".window-shell", { opacity: 0, y: 18, duration: 0.55, ease: "power2.out" }, 0);
      tl.from(".rail", { opacity: 0, x: 24, duration: 0.6, ease: "power2.out" }, 0.12);
      tl.from(".caption", { opacity: 0, y: 18, duration: 0.3, stagger: 0.03 }, 0.35);
      tl.from(".logo-card", { opacity: 0, scale: 0.94, duration: 0.45, ease: "power2.out" }, ${Math.max(20, duration - 13)});
      window.__timelines["main"] = tl;
    </script>
  </body>
</html>
`;
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--video") parsed.video = values[++index];
    else if (value === "--output") parsed.output = values[++index];
    else if (value === "--work-dir") parsed.workDir = values[++index];
    else if (value === "--poster") parsed.poster = values[++index];
    else if (value === "--duration") parsed.duration = values[++index];
    else if (value === "--fps") parsed.fps = values[++index];
    else if (value === "--quality") parsed.quality = values[++index];
    else if (value === "--workers") parsed.workers = values[++index];
    else if (value === "--voice") parsed.voice = values[++index];
    else if (value === "--speed") parsed.speed = values[++index];
    else if (value === "--tts") parsed.tts = values[++index];
    else if (value === "--audio-cues") parsed.audioCues = values[++index];
    else if (value === "--hyperframes") parsed.hyperframes = values[++index];
  }
  return parsed;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
