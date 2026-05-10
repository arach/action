#!/usr/bin/env bun

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

const args = parseArgs(process.argv.slice(2));
const videoPath = resolve(args.video || "");
if (!videoPath || !existsSync(videoPath)) {
  throw new Error("Missing --video <path>");
}

const ffmpeg = process.env.FFMPEG_BIN || "ffmpeg";
const ffprobe = process.env.FFPROBE_BIN || "ffprobe";
const outputPath = resolve(args.output || videoPath.replace(/\.(mov|mp4)$/i, "-narrated.mp4"));
const workDir = resolve(args.workDir || join(dirname(videoPath), "narration"));
const modelId = args.modelId || process.env.ACTION_TTS_ELEVEN_MODEL_ID || "eleven_multilingual_v2";
const voiceName = args.voiceName || process.env.ACTION_TTS_ELEVEN_VOICE_NAME || "Rachel";
const voiceId = args.voiceId || process.env.ACTION_TTS_ELEVEN_VOICE_ID || await resolveVoiceId(voiceName);
const segments = narrationSegments();

mkdirSync(workDir, { recursive: true });
writeFileSync(
  join(workDir, "narration-plan.json"),
  `${JSON.stringify({ videoPath, outputPath, modelId, voiceName, voiceId, segments }, null, 2)}\n`,
);

const audioFiles = [];
for (let index = 0; index < segments.length; index += 1) {
  const segment = segments[index];
  const audioPath = join(workDir, `segment-${String(index + 1).padStart(2, "0")}.mp3`);
  await synthesizeSpeech({ text: segment.text, voiceId, modelId, outputPath: audioPath });
  audioFiles.push(audioPath);
}

const duration = probeDuration(videoPath);
const filterParts = [`anullsrc=channel_layout=stereo:sample_rate=44100,atrim=duration=${duration.toFixed(3)}[base]`];
const mixInputs = ["[base]"];
for (let index = 0; index < segments.length; index += 1) {
  const delayMs = Math.max(0, Math.round(segments[index].at * 1000));
  filterParts.push(`[${index + 1}:a]adelay=${delayMs}|${delayMs},volume=1.0[a${index}]`);
  mixInputs.push(`[a${index}]`);
}
filterParts.push(`${mixInputs.join("")}amix=inputs=${mixInputs.length}:duration=first:dropout_transition=0[aout]`);

const ffmpegArgs = [
  "-y",
  "-i", videoPath,
  ...audioFiles.flatMap((audioPath) => ["-i", audioPath]),
  "-filter_complex", filterParts.join(";"),
  "-map", "0:v:0",
  "-map", "[aout]",
  "-c:v", "libx264",
  "-profile:v", "high",
  "-pix_fmt", "yuv420p",
  "-crf", "20",
  "-preset", "medium",
  "-c:a", "aac",
  "-b:a", "160k",
  "-movflags", "+faststart",
  "-shortest",
  outputPath,
];

const result = spawnSync(ffmpeg, ffmpegArgs, { stdio: "inherit" });
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

console.log(JSON.stringify({ status: "narrated", outputPath, workDir, segments: segments.length }, null, 2));

async function synthesizeSpeech({ text, voiceId, modelId, outputPath }) {
  const apiKey = elevenLabsApiKey();
  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}/stream?output_format=mp3_44100_128`,
    {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        "content-type": "application/json",
        "accept": "audio/mpeg",
      },
      body: JSON.stringify({
        text,
        model_id: modelId,
        voice_settings: {
          stability: 0.46,
          similarity_boost: 0.78,
          style: 0.18,
          use_speaker_boost: true,
        },
      }),
    },
  );

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`ElevenLabs TTS failed (${response.status}): ${detail.slice(0, 300)}`);
  }

  await Bun.write(outputPath, await response.arrayBuffer());
}

async function resolveVoiceId(name) {
  const fallbackVoiceId = "21m00Tcm4TlvDq8ikWAM";
  try {
    const response = await fetch("https://api.elevenlabs.io/v1/voices", {
      headers: { "xi-api-key": elevenLabsApiKey() },
    });
    if (!response.ok) {
      return fallbackVoiceId;
    }
    const payload = await response.json();
    const voices = Array.isArray(payload.voices) ? payload.voices : [];
    const requested = voices.find((voice) => String(voice.name || "").toLowerCase() === name.toLowerCase());
    return requested?.voice_id || voices[0]?.voice_id || fallbackVoiceId;
  } catch {
    return fallbackVoiceId;
  }
}

function elevenLabsApiKey() {
  if (process.env.ELEVENLABS_API_KEY) {
    return process.env.ELEVENLABS_API_KEY.trim();
  }

  const secret = execFileSync("secret", ["get", "ELEVENLABS_API_KEY"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
  if (!secret) {
    throw new Error("ELEVENLABS_API_KEY is not available");
  }
  return secret;
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

function narrationSegments() {
  return [
    {
      at: 0.35,
      text: "Mira is driving a real Chrome profile while Action records the exact macOS window.",
    },
    {
      at: 5.1,
      text: "First, Action resolves the omnibox and performs visible mouse and keyboard actions.",
    },
    {
      at: 11.8,
      text: "The overlay turns the agent loop into something you can watch: observe, resolve, act, inspect.",
    },
    {
      at: 18.4,
      text: "For browser work, Mira can also lean on the Chrome Companion extension for page-level inspection.",
    },
    {
      at: 24.1,
      text: "Midjourney is the visual payoff, but the demo is really about the native capture and inspection loop.",
    },
    {
      at: 31.0,
      text: "At the end, Action saves the video, screenshot, trace, and finished marker as a real artifact.",
    },
  ];
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--video") {
      parsed.video = values[++index];
    } else if (value === "--output") {
      parsed.output = values[++index];
    } else if (value === "--work-dir") {
      parsed.workDir = values[++index];
    } else if (value === "--voice-id") {
      parsed.voiceId = values[++index];
    } else if (value === "--voice-name") {
      parsed.voiceName = values[++index];
    } else if (value === "--model-id") {
      parsed.modelId = values[++index];
    }
  }
  return parsed;
}
