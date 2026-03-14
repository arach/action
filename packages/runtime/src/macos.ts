import { execFile } from "node:child_process";
import { access, mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { promisify } from "node:util";

import type {
  BackdropPreset,
  CaptureEngine,
  CaptureProfile,
  EngineDiagnostics,
  ResolvedTarget,
  RuntimeAction,
  RuntimeArtifact,
  StagePresentation,
  StageViewport,
  SurfaceRef,
  TargetApp,
  TargetQuery,
} from "@action/protocol";

const execFileAsync = promisify(execFile);

function appSurfaceId(app: TargetApp): string {
  return `surface_${app.bundleId.replace(/[^a-z0-9]+/gi, "_").toLowerCase()}`;
}

function calculatorButtonName(query: TargetQuery): string {
  if (query.semanticId === "calculator.operator.plus") {
    return "Add";
  }

  if (query.semanticId === "calculator.operator.equals") {
    return "Equals";
  }

  return query.text ?? query.semanticId ?? "unknown";
}

export class MacOSCommandEngine implements CaptureEngine {
  private readonly surfaces = new Map<string, TargetApp>();
  private activeCapturePath?: string;
  private activeCaptureStopPath?: string;
  private activeCaptureFinishedPath?: string;
  private activeViewport?: StageViewport;
  private focusedSurfaceId?: string;
  private overlayStatePath?: string;
  private overlayStopPath?: string;
  private overlayLogPath?: string;
  private overlayActive = false;
  private overlayPid?: number;

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

  async presentStage(presentation: StagePresentation): Promise<void> {
    const paths = this.ensureOverlayPaths(presentation.sessionId);
    this.overlayStatePath = paths.statePath;
    this.overlayStopPath = paths.stopPath;
    this.overlayLogPath = paths.logPath;

    await mkdir(dirname(paths.statePath), { recursive: true });
    await rm(paths.stopPath, { force: true });
    await rm(paths.logPath, { force: true });
    await this.writeOverlayState(paths.statePath, presentation);

    if (this.overlayActive) {
      return;
    }

    await this.writeOverlayState(paths.statePath, presentation);

    const { stdout } = await this.runHost(
      "stage-overlay",
      "--state-file",
      paths.statePath,
      "--stop-file",
      paths.stopPath,
      "--debug-log",
      paths.logPath,
    );
    const response = JSON.parse(stdout) as { detail?: string };
    this.overlayPid = response.detail ? Number(response.detail) : undefined;
    this.overlayActive = true;
  }

  async clearStage(): Promise<void> {
    if (this.overlayStopPath) {
      await writeFile(this.overlayStopPath, "stop\n");
    }

    if (this.overlayPid) {
      try {
        await execFileAsync("kill", ["-TERM", String(this.overlayPid)]);
      } catch {}

      await new Promise((resolve) => setTimeout(resolve, 150));

      try {
        process.kill(this.overlayPid, 0);
        await execFileAsync("kill", ["-KILL", String(this.overlayPid)]);
      } catch {}
    }

    if (this.overlayStatePath) {
      await rm(this.overlayStatePath, { force: true });
    }

    if (this.overlayStopPath) {
      await rm(this.overlayStopPath, { force: true });
    }

    this.overlayActive = false;
    this.overlayPid = undefined;
    this.overlayLogPath = undefined;
    this.overlayStopPath = undefined;
    this.overlayStatePath = undefined;
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

    await this.runHost("activate-app", "--bundle-id", app.bundleId);
    this.focusedSurfaceId = surfaceId;
  }

  async configureViewport(viewport: StageViewport): Promise<void> {
    this.activeViewport = viewport;

    const surfaceId = viewport.surfaceId ?? this.focusedSurfaceId;
    if (!surfaceId) {
      return;
    }

    const app = this.surfaces.get(surfaceId);
    if (!app) {
      return;
    }

    await this.runHost(
      "set-window-frame",
      "--bundle-id",
      app.bundleId,
      "--x",
      String(viewport.bounds.x),
      "--y",
      String(viewport.bounds.y),
      "--width",
      String(viewport.bounds.width),
      "--height",
      String(viewport.bounds.height),
    );
  }

  async startCapture(request: { outputPath: string; viewport?: StageViewport; profile?: CaptureProfile }): Promise<void> {
    const viewport = request.viewport ?? this.activeViewport;
    if (!viewport) {
      throw new Error("No viewport is configured for capture.");
    }

    await mkdir(dirname(request.outputPath), { recursive: true });
    await rm(request.outputPath, { force: true });
    this.activeCapturePath = request.outputPath;
    this.activeCaptureStopPath = `${request.outputPath}.stop`;
    this.activeCaptureFinishedPath = `${request.outputPath}.finished`;
    await rm(this.activeCaptureStopPath, { force: true });
    await rm(this.activeCaptureFinishedPath, { force: true });
    await this.startRecordingSession(
      viewport,
      request.outputPath,
      this.activeCaptureStopPath,
      this.activeCaptureFinishedPath,
      request.profile ?? "draft",
    );
  }

  async pauseCapture(): Promise<void> {}

  async resumeCapture(): Promise<void> {}

  async stopCapture(): Promise<RuntimeArtifact> {
    const path = this.activeCapturePath ?? resolve(process.cwd(), "artifacts", "sessions", "macos", "capture.mov");
    const stopPath = this.activeCaptureStopPath;
    const finishedPath = this.activeCaptureFinishedPath;

    if (!stopPath) {
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

    await writeFile(stopPath, "stop\n");
    await this.waitForCaptureCompletion(path, finishedPath);
    await rm(stopPath, { force: true });
    if (finishedPath) {
      await rm(finishedPath, { force: true });
    }
    this.activeCaptureStopPath = undefined;
    this.activeCaptureFinishedPath = undefined;

    return {
      kind: "raw-capture",
      path,
    };
  }

  async captureScreenshot(path: string): Promise<RuntimeArtifact> {
    const viewport = this.activeViewport;
    if (!viewport) {
      throw new Error("No viewport is configured for screenshot capture.");
    }

    await mkdir(dirname(path), { recursive: true });
    await rm(path, { force: true });
    await this.runHost(
      "screenshot-region",
      "--x",
      String(viewport.bounds.x),
      "--y",
      String(viewport.bounds.y),
      "--width",
      String(viewport.bounds.width),
      "--height",
      String(viewport.bounds.height),
      "--output",
      path,
    );
    await this.waitForFile(path, 1);

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
      await this.runHost("type-text", "--text", text);
      return;
    }

    if (action.kind === "press-key") {
      const key = String(action.input?.key ?? "");
      await this.runHost("press-key", "--key", key);
      return;
    }

    if (action.kind === "click") {
      const buttonName = calculatorButtonName(target ? { text: target.label, semanticId: target.id } : action.target ?? {});
      await this.runHost("click-calculator-button", "--button", buttonName);
      return;
    }
  }

  async replayArtifact(path: string): Promise<void> {
    await execFileAsync("open", [path]);
  }

  private runHost(command: string, ...args: string[]) {
    return execFileAsync(this.nativeHostPath, [command, ...args]);
  }

  private async startRecordingSession(
    viewport: StageViewport,
    outputPath: string,
    stopPath: string,
    finishedPath: string,
    profile: CaptureProfile,
  ): Promise<void> {
    const fps = profile === "draft" ? "15" : "30";
    const scale = profile === "draft" ? "0.75" : "1";

    await this.runHost(
      "record-region",
      "--x",
      String(viewport.bounds.x),
      "--y",
      String(viewport.bounds.y),
      "--width",
      String(viewport.bounds.width),
      "--height",
      String(viewport.bounds.height),
      "--fps",
      fps,
      "--scale",
      scale,
      "--output",
      outputPath,
      "--stop-file",
      stopPath,
      "--finished-file",
      finishedPath,
    );
  }

  private async waitForCaptureCompletion(path: string, finishedPath?: string): Promise<void> {
    if (finishedPath) {
      await this.waitForFile(finishedPath, 1);
      const status = (await readFile(finishedPath, "utf8")).trim();
      if (status.startsWith("error:")) {
        throw new Error(`Native capture failed: ${status.slice("error:".length).trim()}`);
      }
    }

    await this.waitForFile(path, 1);
  }

  private async waitForFile(path: string, minBytes: number): Promise<void> {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      try {
        await access(path);
        const file = await stat(path);
        if (file.size >= minBytes) {
          return;
        }
      } catch {}

      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    throw new Error(`Timed out waiting for file ${path}`);
  }

  private ensureOverlayPaths(sessionId: string) {
    const root = resolve(process.cwd(), "artifacts", "overlays", sessionId);
    return {
      statePath: resolve(root, "stage.json"),
      stopPath: resolve(root, "stage.stop"),
      logPath: resolve(root, "stage.log"),
    };
  }

  private async writeOverlayState(path: string, presentation: StagePresentation): Promise<void> {
    const tempPath = `${path}.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`;
    await writeFile(tempPath, `${JSON.stringify(presentation, null, 2)}\n`);
    await rename(tempPath, path);
  }
}
