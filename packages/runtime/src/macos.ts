import { execFile } from "node:child_process";
import { access, mkdir, rm, stat, writeFile } from "node:fs/promises";
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
  private activeViewport?: StageViewport;
  private focusedSurfaceId?: string;

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
    await rm(this.activeCaptureStopPath, { force: true });
    await this.startRecordingSession(viewport, request.outputPath, this.activeCaptureStopPath, request.profile ?? "draft");
  }

  async pauseCapture(): Promise<void> {}

  async resumeCapture(): Promise<void> {}

  async stopCapture(): Promise<RuntimeArtifact> {
    const path = this.activeCapturePath ?? resolve(process.cwd(), "artifacts", "sessions", "macos", "capture.mov");
    const stopPath = this.activeCaptureStopPath;

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
    await this.waitForCaptureFile(path);
    await rm(stopPath, { force: true });
    this.activeCaptureStopPath = undefined;

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
    );
  }

  private async waitForCaptureFile(path: string): Promise<void> {
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
}
