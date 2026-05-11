import { access, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";

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

async function readJsonFile<T>(path: string): Promise<T> {
  return JSON.parse(await readFile(path, "utf8")) as T;
}

function resolveFromRoot(root: string, path: string): string {
  return isAbsolute(path) ? path : resolve(root, path);
}

interface HandoffManifest {
  kind?: string;
  source?: {
    sessionId?: string;
    sessionPath?: string;
    mode?: string;
    targetApp?: string;
  };
  verification?: {
    status?: string;
  };
  primaryVideo?: {
    path?: string;
    sourcePath?: string;
    width?: number;
    height?: number;
    durationSeconds?: number;
    frameCount?: number;
    averageFrameRate?: number;
    bitRate?: number;
    codec?: string;
  };
  artifacts?: Array<{
    kind?: string;
    exportedPath?: string;
    sourcePath?: string;
  }>;
  preframe?: {
    intake?: string;
    suggestedProject?: string;
    tags?: string[];
  };
}

export interface SourceMaterialInventoryAsset {
  id: string;
  exportDir: string;
  handoffManifestPath: string;
  sessionId?: string;
  sessionPath?: string;
  targetApp?: string;
  verificationStatus?: string;
  primaryVideoPath?: string;
  sourceVideoPath?: string;
  width?: number;
  height?: number;
  durationSeconds?: number;
  frameCount?: number;
  averageFrameRate?: number;
  bitRate?: number;
  codec?: string;
  artifactCount: number;
  tags: string[];
}

export interface SourceMaterialInventory {
  schemaVersion: 1;
  kind: "source-material-index";
  generatedAt: string;
  exportsDir: string;
  count: number;
  assets: SourceMaterialInventoryAsset[];
}

export interface SourceMaterialInventoryOptions {
  exportsDir?: string;
  outputPath?: string;
  root?: string;
}

export async function collectSourceMaterialInventory(
  options: SourceMaterialInventoryOptions = {},
): Promise<SourceMaterialInventory> {
  const root = options.root ?? process.cwd();
  const exportsDir = resolveFromRoot(root, options.exportsDir ?? "artifacts/exports");
  const entries = await readdir(exportsDir, { withFileTypes: true }).catch(() => []);
  const assets: SourceMaterialInventoryAsset[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const exportDir = resolve(exportsDir, entry.name);
    const handoffManifestPath = resolve(exportDir, "mira-handoff.json");
    if (!await pathExists(handoffManifestPath)) {
      continue;
    }

    const handoff = await readJsonFile<HandoffManifest>(handoffManifestPath);
    assets.push({
      id: entry.name,
      exportDir,
      handoffManifestPath,
      sessionId: handoff.source?.sessionId,
      sessionPath: handoff.source?.sessionPath,
      targetApp: handoff.source?.targetApp,
      verificationStatus: handoff.verification?.status,
      primaryVideoPath: handoff.primaryVideo?.path,
      sourceVideoPath: handoff.primaryVideo?.sourcePath,
      width: handoff.primaryVideo?.width,
      height: handoff.primaryVideo?.height,
      durationSeconds: handoff.primaryVideo?.durationSeconds,
      frameCount: handoff.primaryVideo?.frameCount,
      averageFrameRate: handoff.primaryVideo?.averageFrameRate,
      bitRate: handoff.primaryVideo?.bitRate,
      codec: handoff.primaryVideo?.codec,
      artifactCount: handoff.artifacts?.length ?? 0,
      tags: handoff.preframe?.tags ?? [],
    });
  }

  assets.sort((left, right) => left.id.localeCompare(right.id));

  const inventory: SourceMaterialInventory = {
    schemaVersion: 1,
    kind: "source-material-index",
    generatedAt: now(),
    exportsDir,
    count: assets.length,
    assets,
  };

  if (options.outputPath) {
    const outputPath = resolveFromRoot(root, options.outputPath);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, `${JSON.stringify(inventory, null, 2)}\n`);
  }

  return inventory;
}
