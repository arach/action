import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, extname, isAbsolute, resolve } from "node:path";

import type {
  PersistedRuntimeSession,
  RuntimeArtifact,
  SessionArtifactEntry,
  SessionArtifactManifest,
} from "@action/protocol";
import { verifyMediaAsset } from "./media-verification.js";

function now(): string {
  return new Date().toISOString();
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function resolveSessionDir(sessionIdOrPath: string, root = process.cwd()): string {
  if (isAbsolute(sessionIdOrPath) || sessionIdOrPath.includes("/")) {
    return resolve(root, sessionIdOrPath);
  }

  return resolve(root, "artifacts", "sessions", sessionIdOrPath);
}

function resolveOutputDir(input: string | undefined, sessionId: string, root = process.cwd()): string {
  return resolve(root, input ?? resolve("artifacts", "exports", sessionId));
}

async function readJsonFile<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, "utf8")) as T;
}

function artifactPath(outputDir: string, entry: SessionArtifactEntry): string {
  return entry.path || resolve(outputDir, entry.relativePath);
}

function artifactExtension(path: string, fallback: string): string {
  return extname(path) || fallback;
}

function exportedName(entry: SessionArtifactEntry, index: number): string {
  if (entry.kind === "raw-capture") {
    return `capture${artifactExtension(entry.path, ".mov")}`;
  }

  if (entry.kind === "trace") {
    return "trace.json";
  }

  if (entry.kind === "source-run-report") {
    return "source-run-report.json";
  }

  if (entry.kind === "screenshot") {
    const source = typeof entry.metadata?.source === "string" ? entry.metadata.source : undefined;
    const scope = typeof entry.metadata?.scope === "string" ? entry.metadata.scope : undefined;
    const suffix = source ?? scope ?? `screenshot-${index + 1}`;
    return `${suffix}${artifactExtension(entry.path, ".png")}`;
  }

  return basename(entry.path || entry.relativePath);
}

export interface SessionAssetExportOptions {
  sessionIdOrPath: string;
  outputDir?: string;
  root?: string;
}

export interface SessionAssetExportResult {
  ok: true;
  exportDir: string;
  handoffManifestPath: string;
  sourceSessionPath: string;
  primaryVideoPath: string;
  copiedArtifacts: Array<{
    kind: RuntimeArtifact["kind"];
    sourcePath: string;
    exportedPath: string;
  }>;
}

export async function exportSessionAssets(
  options: SessionAssetExportOptions,
): Promise<SessionAssetExportResult> {
  const root = options.root ?? process.cwd();
  const sourceSessionPath = resolveSessionDir(options.sessionIdOrPath, root);
  const sessionPath = resolve(sourceSessionPath, "session.json");
  const manifestPath = resolve(sourceSessionPath, "manifest.json");

  if (!await pathExists(sessionPath)) {
    throw new Error(`No session.json found for ${options.sessionIdOrPath}`);
  }

  if (!await pathExists(manifestPath)) {
    throw new Error(`No manifest.json found for ${options.sessionIdOrPath}`);
  }

  const session = await readJsonFile<PersistedRuntimeSession>(sessionPath);
  const manifest = await readJsonFile<SessionArtifactManifest>(manifestPath);
  const exportDir = resolveOutputDir(options.outputDir, session.id, root);
  const primaryCapture = manifest.artifacts.find((entry) => entry.kind === "raw-capture");

  if (session.state !== "completed") {
    throw new Error(`Session ${session.id} is ${session.state}, not completed`);
  }

  if (!primaryCapture) {
    throw new Error(`Session ${session.id} has no raw-capture artifact`);
  }

  const primaryCapturePath = artifactPath(manifest.outputDir, primaryCapture);
  if (!await pathExists(primaryCapturePath)) {
    throw new Error(`Primary capture is missing: ${primaryCapturePath}`);
  }

  await mkdir(exportDir, { recursive: true });

  const copiedArtifacts: SessionAssetExportResult["copiedArtifacts"] = [];
  for (const [index, entry] of manifest.artifacts.entries()) {
    const sourcePath = artifactPath(manifest.outputDir, entry);
    if (!await pathExists(sourcePath)) {
      continue;
    }

    const exportedPath = resolve(exportDir, exportedName(entry, index));
    await mkdir(dirname(exportedPath), { recursive: true });
    await copyFile(sourcePath, exportedPath);
    copiedArtifacts.push({
      kind: entry.kind,
      sourcePath,
      exportedPath,
    });
  }

  const sourceRunReportPath = resolve(sourceSessionPath, "source-run-report.json");
  if (await pathExists(sourceRunReportPath)) {
    const exportedPath = resolve(exportDir, "source-run-report.json");
    await copyFile(sourceRunReportPath, exportedPath);
    copiedArtifacts.push({
      kind: "source-run-report",
      sourcePath: sourceRunReportPath,
      exportedPath,
    });
  }

  await copyFile(sessionPath, resolve(exportDir, "session.json"));
  await copyFile(manifestPath, resolve(exportDir, "manifest.json"));

  const primaryVideo = copiedArtifacts.find((entry) => entry.kind === "raw-capture");
  if (!primaryVideo) {
    throw new Error(`Primary capture could not be exported: ${primaryCapturePath}`);
  }
  const mediaVerification = await verifyMediaAsset({ path: primaryVideo.exportedPath });
  if (mediaVerification.status === "failed") {
    const detail = mediaVerification.issues.map((issue) => issue.message).join("; ");
    throw new Error(`Primary capture failed media verification: ${detail}`);
  }

  const handoffManifest = {
    schemaVersion: 1,
    kind: "mira-session-handoff",
    generatedAt: now(),
    source: {
      sessionId: session.id,
      sessionPath: sourceSessionPath,
      manifestPath,
      mode: session.mode,
      targetApp: session.targetApp,
    },
    verification: {
      status: mediaVerification.status,
      basis: [
        "session.state=completed",
        "raw-capture exists",
        "trace and manifest persisted",
        mediaVerification.status === "verified"
          ? "media probe passed"
          : "media probe completed with warnings",
      ],
      media: mediaVerification,
    },
    primaryVideo: {
      path: primaryVideo.exportedPath,
      sourcePath: primaryVideo.sourcePath,
      format: artifactExtension(primaryVideo.exportedPath, ".mov").slice(1),
      width: mediaVerification.width,
      height: mediaVerification.height,
      durationSeconds: mediaVerification.durationSeconds,
      codec: mediaVerification.codec,
      frameCount: mediaVerification.frameCount,
      averageFrameRate: mediaVerification.averageFrameRate,
      bitRate: mediaVerification.bitRate ?? mediaVerification.containerBitRate,
    },
    artifacts: copiedArtifacts,
    preframe: {
      intake: "raw-source-material",
      suggestedProject: session.targetApp ?? session.id,
      tags: ["mira", "action", session.mode, session.targetApp].filter(Boolean),
    },
  };
  const handoffManifestPath = resolve(exportDir, "mira-handoff.json");
  await writeFile(handoffManifestPath, JSON.stringify(handoffManifest, null, 2));

  return {
    ok: true,
    exportDir,
    handoffManifestPath,
    sourceSessionPath,
    primaryVideoPath: primaryVideo.exportedPath,
    copiedArtifacts,
  };
}
