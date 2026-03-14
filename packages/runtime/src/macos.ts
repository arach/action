import { execFile, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { promisify } from "node:util";

import type {
  BackdropPreset,
  CaptureEngine,
  EngineDiagnostics,
  ResolvedTarget,
  RuntimeAction,
  RuntimeArtifact,
  StageViewport,
  SurfaceRef,
  TargetApp,
  TargetQuery,
} from "@action/protocol";

const execFileAsync = promisify(execFile);

function appSurfaceId(app: TargetApp): string {
  return `surface_${app.bundleId.replace(/[^a-z0-9]+/gi, "_").toLowerCase()}`;
}

function shellQuote(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
}

function calculatorButtonName(query: TargetQuery): string {
  if (query.semanticId === "calculator.operator.plus") {
    return "+";
  }

  if (query.semanticId === "calculator.operator.equals") {
    return "=";
  }

  return query.text ?? query.semanticId ?? "unknown";
}

export class MacOSCommandEngine implements CaptureEngine {
  private readonly surfaces = new Map<string, TargetApp>();
  private activeCapturePath?: string;
  private focusedSurfaceId?: string;
  private activeCaptureProcess?: ChildProcessWithoutNullStreams;

  constructor(
    private readonly nativeHostPath = "native/engine/scripts/run-app-host.sh",
  ) {}

  async diagnostics(): Promise<EngineDiagnostics> {
    try {
      const { stdout } = await this.runHost("status");

      return JSON.parse(stdout) as EngineDiagnostics;
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Unknown diagnostics error";

      return {
        accessibility: "unknown",
        screenRecording: "unknown",
        notes: [detail],
      };
    }
  }

  async requestPermissions(): Promise<EngineDiagnostics> {
    const { stdout } = await this.runHost("request");
    return JSON.parse(stdout) as EngineDiagnostics;
  }

  async openPermissionSettings(kind: "accessibility" | "screen-recording"): Promise<void> {
    await this.runHost(
      kind === "accessibility"
        ? "open-accessibility-settings"
        : "open-screen-recording-settings",
    );
  }

  async setBackdrop(_backdrop: BackdropPreset): Promise<void> {}

  async launchApp(app: TargetApp): Promise<SurfaceRef> {
    await execFileAsync("open", ["-a", app.name]);

    const id = appSurfaceId(app);
    this.surfaces.set(id, app);

    return {
      id,
      kind: "window",
      label: `${app.name} Window`,
    };
  }

  async focusSurface(surfaceId: string): Promise<void> {
    const app = this.surfaces.get(surfaceId);

    if (!app) {
      throw new Error(`Unknown surface: ${surfaceId}`);
    }

    await execFileAsync("osascript", [
      "-e",
      `tell application "${shellQuote(app.name)}" to activate`,
    ]);
    this.focusedSurfaceId = surfaceId;
  }

  async configureViewport(_viewport: StageViewport): Promise<void> {}

  async startCapture(request: { outputPath: string }): Promise<void> {
    const surfaceId = this.focusedSurfaceId;
    if (!surfaceId) {
      throw new Error("No focused surface is available for capture.");
    }

    const app = this.surfaces.get(surfaceId);
    if (!app) {
      throw new Error(`No app is registered for surface ${surfaceId}.`);
    }

    await mkdir(dirname(request.outputPath), { recursive: true });
    this.activeCapturePath = request.outputPath;
    this.activeCaptureProcess = await this.startRecordingProcess(app.bundleId, request.outputPath);
  }

  async pauseCapture(): Promise<void> {}

  async resumeCapture(): Promise<void> {}

  async stopCapture(): Promise<RuntimeArtifact> {
    const path = this.activeCapturePath ?? "artifacts/sessions/macos/capture.mov";
    const child = this.activeCaptureProcess;

    if (!child) {
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, "");

      return {
        kind: "raw-capture",
        path,
        metadata: {
          placeholder: true,
          reason: "Capture process was not active.",
        },
      };
    }

    child.stdin.end();
    const result = await this.waitForProcessExit(child);
    this.activeCaptureProcess = undefined;

    if (result.code !== 0) {
      throw new Error(result.stderr || `Capture process exited with code ${result.code}`);
    }

    return {
      kind: "raw-capture",
      path,
    };
  }

  async captureScreenshot(path: string): Promise<RuntimeArtifact> {
    const surfaceId = this.focusedSurfaceId;
    if (!surfaceId) {
      throw new Error("No focused surface is available for screenshot capture.");
    }

    const app = this.surfaces.get(surfaceId);
    if (!app) {
      throw new Error(`No app is registered for surface ${surfaceId}.`);
    }

    await mkdir(dirname(path), { recursive: true });
    await this.runHost("screenshot-app-window", "--bundle-id", app.bundleId, "--output", path);

    return {
      kind: "screenshot",
      path,
    };
  }

  async resolveTarget(query: TargetQuery): Promise<ResolvedTarget> {
    return {
      id: query.semanticId ?? query.text ?? "target",
      mode: query.point ? "coordinate" : "semantic",
      confidence: 0.92,
      label: query.semanticId ?? query.text ?? "Resolved Target",
      surfaceId: query.surfaceId,
    };
  }

  async performAction(action: RuntimeAction, target?: ResolvedTarget): Promise<void> {
    if (action.kind === "type") {
      const text = String(action.input?.text ?? "");
      await execFileAsync("osascript", [
        "-e",
        "tell application \"System Events\" to keystroke " + JSON.stringify(text),
      ]);
      return;
    }

    if (action.kind === "press-key") {
      const key = String(action.input?.key ?? "");
      await execFileAsync("osascript", [
        "-e",
        "tell application \"System Events\" to keystroke " + JSON.stringify(key),
      ]);
      return;
    }

    if (action.kind === "click") {
      const buttonName = calculatorButtonName(target ? { text: target.label, semanticId: target.id } : action.target ?? {});
      await execFileAsync("osascript", [
        "-e",
        `tell application "System Events" to tell process "Calculator" to click button "${shellQuote(buttonName)}" of window 1`,
      ]);
      return;
    }
  }

  async replayArtifact(path: string): Promise<void> {
    await execFileAsync("open", [path]);
  }

  private runHost(command: string, ...args: string[]) {
    return execFileAsync(this.nativeHostPath, [command, ...args]);
  }

  private startRecordingProcess(bundleId: string, outputPath: string): Promise<ChildProcessWithoutNullStreams> {
    return new Promise((resolve, reject) => {
      const child = spawn(
        this.nativeHostPath,
        [
          "record-app-window",
          "--bundle-id",
          bundleId,
          "--output",
          outputPath,
        ],
        {
          stdio: ["pipe", "pipe", "pipe"],
        },
      );

      let stdout = "";
      let stderr = "";
      let settled = false;

      child.stdout.on("data", (chunk: Buffer) => {
        stdout += chunk.toString("utf8");
        if (settled || !stdout.includes("\n")) {
          return;
        }

        settled = true;
        resolve(child);
      });

      child.stderr.on("data", (chunk: Buffer) => {
        stderr += chunk.toString("utf8");
      });

      child.on("exit", (code) => {
        if (settled) {
          return;
        }

        reject(new Error(stderr || stdout || `Capture process exited before start with code ${code}`));
      });

      child.on("error", (error) => {
        if (settled) {
          return;
        }

        reject(error);
      });
    });
  }

  private waitForProcessExit(child: ChildProcessWithoutNullStreams): Promise<{
    code: number | null;
    stderr: string;
  }> {
    return new Promise((resolve) => {
      let stderr = "";

      child.stderr.on("data", (chunk: Buffer) => {
        stderr += chunk.toString("utf8");
      });

      child.on("exit", (code) => {
        resolve({ code, stderr });
      });
    });
  }
}
