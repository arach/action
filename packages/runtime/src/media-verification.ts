import { execFile } from "node:child_process";
import { access, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type MediaVerificationStatus = "verified" | "warning" | "failed";

export interface MediaVerificationIssue {
  level: "warning" | "error";
  code: string;
  message: string;
}

export interface MediaVerificationReport {
  path: string;
  generatedAt: string;
  status: MediaVerificationStatus;
  exists: boolean;
  sizeBytes?: number;
  durationSeconds?: number;
  width?: number;
  height?: number;
  codec?: string;
  averageFrameRate?: number;
  frameCount?: number;
  bitRate?: number;
  containerBitRate?: number;
  formatName?: string;
  ffprobePath?: string;
  issues: MediaVerificationIssue[];
}

export interface MediaVerificationOptions {
  path: string;
  minDurationSeconds?: number;
  minFrameCount?: number;
  minWidth?: number;
  minHeight?: number;
}

interface FFProbeStream {
  codec_name?: string;
  codec_type?: string;
  width?: number;
  height?: number;
  avg_frame_rate?: string;
  nb_frames?: string;
  bit_rate?: string;
}

interface FFProbeFormat {
  duration?: string;
  size?: string;
  bit_rate?: string;
  format_name?: string;
}

interface FFProbePayload {
  streams?: FFProbeStream[];
  format?: FFProbeFormat;
}

function now(): string {
  return new Date().toISOString();
}

function numeric(value: string | number | undefined): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function frameCount(value: string | undefined): number | undefined {
  if (!value || value === "N/A") {
    return undefined;
  }

  return numeric(value);
}

function ratio(value: string | undefined): number | undefined {
  if (!value || value === "0/0") {
    return undefined;
  }

  const [numerator, denominator] = value.split("/").map(Number);
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) {
    return numeric(value);
  }

  return numerator / denominator;
}

async function accessibleExecutable(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function resolveFFProbePath(): Promise<string> {
  const candidates = [
    process.env.ACTION_FFPROBE,
    "/opt/homebrew/bin/ffprobe",
    "/usr/local/bin/ffprobe",
    "ffprobe",
  ].filter((candidate): candidate is string => Boolean(candidate));

  for (const candidate of candidates) {
    if (!candidate.includes("/")) {
      return candidate;
    }

    if (await accessibleExecutable(candidate)) {
      return candidate;
    }
  }

  return "ffprobe";
}

function failedReport(path: string, issue: MediaVerificationIssue): MediaVerificationReport {
  return {
    path,
    generatedAt: now(),
    status: issue.level === "error" ? "failed" : "warning",
    exists: false,
    issues: [issue],
  };
}

function statusFor(issues: MediaVerificationIssue[]): MediaVerificationStatus {
  if (issues.some((issue) => issue.level === "error")) {
    return "failed";
  }

  return issues.length > 0 ? "warning" : "verified";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export async function verifyMediaAsset(
  options: MediaVerificationOptions,
): Promise<MediaVerificationReport> {
  const path = resolve(options.path);
  const minDurationSeconds = options.minDurationSeconds ?? 1;
  const minFrameCount = options.minFrameCount ?? 5;
  const issues: MediaVerificationIssue[] = [];

  let fileSize: number;
  try {
    const file = await stat(path);
    fileSize = file.size;
  } catch {
    return failedReport(path, {
      level: "error",
      code: "media-missing",
      message: `Media file does not exist: ${path}`,
    });
  }

  if (fileSize <= 0) {
    return {
      path,
      generatedAt: now(),
      status: "failed",
      exists: true,
      sizeBytes: fileSize,
      issues: [{
        level: "error",
        code: "media-empty",
        message: "Media file is empty.",
      }],
    };
  }

  const ffprobePath = await resolveFFProbePath();
  let payload: FFProbePayload;
  try {
    const { stdout } = await execFileAsync(ffprobePath, [
      "-v",
      "error",
      "-show_entries",
      "format=duration,size,bit_rate,format_name",
      "-show_streams",
      "-of",
      "json",
      path,
    ], { maxBuffer: 4 * 1024 * 1024 });
    payload = JSON.parse(stdout) as FFProbePayload;
  } catch (error) {
    const message = errorMessage(error);
    const isMissingProbe = message.includes("ENOENT") || message.includes("not found");
    return {
      path,
      generatedAt: now(),
      status: isMissingProbe ? "warning" : "failed",
      exists: true,
      sizeBytes: fileSize,
      ffprobePath,
      issues: [{
        level: isMissingProbe ? "warning" : "error",
        code: isMissingProbe ? "ffprobe-unavailable" : "ffprobe-failed",
        message: isMissingProbe
          ? "ffprobe is not available, so media metadata could not be verified."
          : `ffprobe could not read the media container: ${message}`,
      }],
    };
  }

  const stream = payload.streams?.find((candidate) => candidate.codec_type === "video");
  if (!stream) {
    issues.push({
      level: "error",
      code: "video-stream-missing",
      message: "No video stream was found in the media file.",
    });
  }

  const durationSeconds = numeric(payload.format?.duration);
  const width = numeric(stream?.width);
  const height = numeric(stream?.height);
  const frames = frameCount(stream?.nb_frames);
  const averageFrameRate = ratio(stream?.avg_frame_rate);
  const bitRate = numeric(stream?.bit_rate);
  const containerBitRate = numeric(payload.format?.bit_rate);

  if (durationSeconds === undefined) {
    issues.push({
      level: "error",
      code: "duration-missing",
      message: "Media duration is missing.",
    });
  } else if (durationSeconds < minDurationSeconds) {
    issues.push({
      level: "warning",
      code: "duration-short",
      message: `Media duration is ${durationSeconds.toFixed(2)}s, below ${minDurationSeconds}s.`,
    });
  }

  if (width === undefined || height === undefined) {
    issues.push({
      level: "error",
      code: "dimensions-missing",
      message: "Video dimensions are missing.",
    });
  } else {
    if (options.minWidth !== undefined && width < options.minWidth) {
      issues.push({
        level: "warning",
        code: "width-small",
        message: `Video width is ${width}px, below ${options.minWidth}px.`,
      });
    }
    if (options.minHeight !== undefined && height < options.minHeight) {
      issues.push({
        level: "warning",
        code: "height-small",
        message: `Video height is ${height}px, below ${options.minHeight}px.`,
      });
    }
  }

  if (frames !== undefined && frames < minFrameCount) {
    issues.push({
      level: "warning",
      code: "frame-count-low",
      message: `Video contains ${frames} frames, below ${minFrameCount}.`,
    });
  }

  if (fileSize < 10_000) {
    issues.push({
      level: "warning",
      code: "file-small",
      message: `Media file is only ${fileSize} bytes.`,
    });
  }

  return {
    path,
    generatedAt: now(),
    status: statusFor(issues),
    exists: true,
    sizeBytes: fileSize,
    durationSeconds,
    width,
    height,
    codec: stream?.codec_name,
    averageFrameRate,
    frameCount: frames,
    bitRate,
    containerBitRate,
    formatName: payload.format?.format_name,
    ffprobePath,
    issues,
  };
}
