import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { access, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { promisify } from "node:util";

import type { Bounds, StageDrapeLevel, StageMode, StageSubject, StageWorld, StageWorldStatus } from "@action/protocol";

const execFileAsync = promisify(execFile);

const DEFAULT_COLOR = "0e0d0a";
const DEFAULT_MODE: StageMode = "drape";
const DEFAULT_LEVEL: StageDrapeLevel = "normal";

export function stageStateDir(): string {
  return resolve(homedir(), "Library/Application Support/Action/stage");
}

export function normalizeHexColor(input: string | undefined): string {
  const raw = (input ?? DEFAULT_COLOR).trim().replace(/^#/, "");
  if (!/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(raw)) {
    throw new Error(`Invalid stage color "${input ?? ""}". Use RRGGBB.`);
  }
  return raw.toLowerCase();
}

export function parseStageWorld(input: {
  mode?: unknown;
  color?: unknown;
  level?: unknown;
  bounds?: unknown;
  subjects?: unknown;
}): StageWorld {
  const mode = input.mode === "space" ? "space" : DEFAULT_MODE;
  const level = input.level === "desktop" ? "desktop" : DEFAULT_LEVEL;
  const color = normalizeHexColor(typeof input.color === "string" ? input.color : undefined);
  const subjects = parseSubjects(input.subjects);
  const bounds = parseBounds(input.bounds);
  return { mode, color, level, subjects, ...(bounds ? { bounds } : {}) };
}

function parseSubjects(value: unknown): StageSubject[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error("subjects must be an array of { bundleId, title? }");
  }
  return value.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`subjects[${index}] must be an object`);
    }
    const record = entry as Record<string, unknown>;
    const bundleId = typeof record.bundleId === "string" ? record.bundleId.trim() : "";
    if (!bundleId) {
      throw new Error(`subjects[${index}].bundleId is required`);
    }
    const title = typeof record.title === "string" && record.title.length > 0 ? record.title : undefined;
    return title ? { bundleId, title } : { bundleId };
  });
}

function parseBounds(value: unknown): Bounds | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("bounds must be { x, y, width, height }");
  }
  const record = value as Record<string, unknown>;
  const x = Number(record.x);
  const y = Number(record.y);
  const width = Number(record.width);
  const height = Number(record.height);
  if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
    throw new Error("bounds must be finite x,y,width,height with positive size");
  }
  return { x, y, width, height };
}

export class StageDirector {
  constructor(
    private readonly nativeHostPath: string,
    private readonly root = stageStateDir(),
  ) {}

  private paths() {
    return {
      stop: resolve(this.root, "drape.stop"),
      log: resolve(this.root, "drape.log"),
      world: resolve(this.root, "world.json"),
    };
  }

  async set(input: Parameters<typeof parseStageWorld>[0]): Promise<StageWorldStatus> {
    const world = parseStageWorld(input);
    await this.clear({ forget: false });

    const paths = this.paths();
    await mkdir(this.root, { recursive: true });
    await rm(paths.stop, { force: true });
    await rm(paths.log, { force: true });

    const args = [
      "drape",
      "--color",
      world.color,
      "--level",
      world.mode === "space" ? "normal" : world.level,
      "--space",
      world.mode,
      "--stop-file",
      paths.stop,
      "--debug-log",
      paths.log,
      "--parent-pid",
      String(process.pid),
    ];
    if (world.bounds) {
      args.push(
        "--bounds",
        `${world.bounds.x},${world.bounds.y},${world.bounds.width},${world.bounds.height}`,
      );
    }

    const { stdout } = await execFileAsync(this.nativeHostPath, args);
    const response = JSON.parse(stdout.trim() || "{}") as { status?: string; detail?: string };
    const pid = response.detail ? Number(response.detail) : undefined;

    const raised: Array<StageSubject & { title: string }> = [];
    for (const subject of world.subjects) {
      const raiseArgs = ["raise-window", "--bundle-id", subject.bundleId];
      if (subject.title) {
        raiseArgs.push("--title", subject.title);
      }
      const raisedResult = await execFileAsync(this.nativeHostPath, raiseArgs);
      const payload = JSON.parse(raisedResult.stdout.trim() || "{}") as { detail?: string };
      const title = payload.detail?.split(": ").slice(1).join(": ") || subject.title || subject.bundleId;
      raised.push({ bundleId: subject.bundleId, title });
    }

    const status: StageWorldStatus = {
      ...world,
      active: true,
      pid: Number.isFinite(pid) ? pid : undefined,
      stopFile: paths.stop,
      raised,
    };
    await writeFile(paths.world, `${JSON.stringify(status, null, 2)}\n`);
    return status;
  }

  async clear(options: { forget?: boolean } = {}): Promise<StageWorldStatus> {
    const paths = this.paths();
    const previous = await this.readWorld();
    if (previous?.stopFile || paths.stop) {
      await mkdir(dirname(paths.stop), { recursive: true });
      await writeFile(paths.stop, "stop\n");
    }
    if (previous?.pid) {
      try {
        await execFileAsync("kill", ["-TERM", String(previous.pid)]);
      } catch {
        // Already gone.
      }
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 180));
    if (options.forget !== false) {
      await rm(paths.world, { force: true });
    }
    return {
      mode: previous?.mode ?? DEFAULT_MODE,
      color: previous?.color ?? DEFAULT_COLOR,
      level: previous?.level ?? DEFAULT_LEVEL,
      subjects: previous?.subjects ?? [],
      bounds: previous?.bounds,
      active: false,
      raised: [],
    };
  }

  async status(): Promise<StageWorldStatus> {
    const world = await this.readWorld();
    if (!world) {
      return {
        mode: DEFAULT_MODE,
        color: DEFAULT_COLOR,
        level: DEFAULT_LEVEL,
        subjects: [],
        active: false,
        raised: [],
      };
    }
    if (world.pid) {
      try {
        process.kill(world.pid, 0);
        return { ...world, active: true };
      } catch {
        return { ...world, active: false, pid: undefined };
      }
    }
    return { ...world, active: false };
  }

  private async readWorld(): Promise<StageWorldStatus | undefined> {
    const path = this.paths().world;
    try {
      await access(path);
      return JSON.parse(await readFile(path, "utf8")) as StageWorldStatus;
    } catch {
      return undefined;
    }
  }
}
