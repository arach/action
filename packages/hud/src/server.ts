import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, resolve } from "node:path";

import { compileScenario, parseScenarioDocument } from "@action/compiler";
import type { EngineDiagnostics, GuidedSessionEvent, HudSnapshot } from "@action/protocol";
import { GuidedCaptureSession, MacOSCommandEngine, MockCaptureEngine } from "@action/runtime";

type EngineMode = "mock" | "macos";

interface HudState {
  engineMode: EngineMode;
  snapshot?: HudSnapshot;
  events: GuidedSessionEvent[];
  sceneSteps: Array<{
    id: string;
    title: string;
    status: "pending" | "active" | "completed" | "failed";
  }>;
  status: "idle" | "staged" | "running" | "completed" | "failed";
  error?: string;
}

class HudController {
  private currentSession?: GuidedCaptureSession;
  private currentTimeline?: ReturnType<typeof compileScenario>["timeline"];
  private readonly listeners = new Set<ServerResponse>();
  private runPromise?: Promise<HudState>;
  private state: HudState = {
    engineMode: "mock",
    events: [],
    sceneSteps: [],
    status: "idle",
  };

  constructor() {
    setInterval(() => {
      void this.pollStageControls();
    }, 220);
  }

  getState(): HudState {
    return this.state;
  }

  async stage(engineMode: EngineMode): Promise<HudState> {
    if (this.state.status === "running") {
      return this.state;
    }

    if (this.currentSession) {
      try {
        await this.currentSession.clearStage();
      } catch {}
      this.currentSession = undefined;
      this.currentTimeline = undefined;
    }

    const scenario = await this.loadScenario("calculator-demo");
    const { timeline } = compileScenario(scenario);
    const initialSteps = timeline.steps.map((step) => ({
      id: step.action.id,
      title: step.action.description,
      status: "pending" as const,
    }));
    const engine = engineMode === "macos"
      ? new MacOSCommandEngine()
      : new MockCaptureEngine();

    const session = new GuidedCaptureSession(engine, {
      sessionId: `session_${scenario.id.replace(/[^a-z0-9]+/gi, "_")}`,
      outputDir: resolve(process.cwd(), "artifacts", "sessions", scenario.id),
      captureProfile: "draft",
      stageHoldMsAfterComplete: -1,
      initialActionDelayMs: 650,
      actionCadenceMs: 900,
    });

    this.currentSession = session;
    this.currentTimeline = timeline;
    this.state = {
      engineMode,
      snapshot: session.snapshot(),
      events: [],
      sceneSteps: initialSteps,
      status: "idle",
    };

    session.onEvent((event) => {
      this.state = {
        ...this.state,
        snapshot: session.snapshot(),
        events: [...this.state.events, event],
        sceneSteps: this.applyStepEvent(this.state.sceneSteps, event),
      };
      this.broadcast();
    });

    try {
      await session.stageScene({
        backdrop: scenario.stage.backdrop,
        viewport: scenario.stage.viewport,
        targetApp: scenario.targetApp,
      });
      this.state = {
        ...this.state,
        snapshot: session.snapshot(),
        status: "staged",
      };
    } catch (error) {
      this.state = {
        ...this.state,
        snapshot: session.snapshot(),
        status: "failed",
        error: error instanceof Error ? error.message : "Unknown HUD stage error",
      };
    }

    this.broadcast();
    return this.state;
  }

  async start(engineMode: EngineMode): Promise<HudState> {
    await this.stage(engineMode);
    if (this.state.status === "failed") {
      return this.state;
    }
    return this.run();
  }

  async run(): Promise<HudState> {
    if (!this.currentSession || !this.currentTimeline) {
      return this.state;
    }
    const session = this.currentSession;
    const timeline = this.currentTimeline;

    if (this.runPromise) {
      return this.runPromise;
    }

    this.runPromise = (async () => {
      this.state = {
        ...this.state,
        status: "running",
        error: undefined,
      };
      this.broadcast();

      try {
        await session.beginRun(timeline);
        await this.pushSnapshot();

        if (session.snapshot().phase === "recording" || session.snapshot().phase === "completing") {
          await session.captureScreenshot("screenshot-viewport-final.png", "viewport");
          await session.captureScreenshot("screenshot-full-final.png", "full");
          await this.pushSnapshot();

          await session.stop();
        }
        this.state = {
          ...this.state,
          snapshot: session.snapshot(),
          status: "completed",
        };
      } catch (error) {
        this.state = {
          ...this.state,
          snapshot: session.snapshot(),
          status: "failed",
          error: error instanceof Error ? error.message : "Unknown HUD run error",
        };
      } finally {
        this.runPromise = undefined;
      }

      this.broadcast();
      return this.state;
    })();

    return this.runPromise;
  }

  async replay(): Promise<HudState> {
    if (!this.currentSession) {
      return this.state;
    }

    try {
      await this.currentSession.replayLastRun();
    } catch (error) {
      this.state = {
        ...this.state,
        error: error instanceof Error ? error.message : "Replay failed",
      };
    }

    this.broadcast();
    return this.state;
  }

  async clear(): Promise<HudState> {
    if (!this.currentSession) {
      this.state = {
        ...this.state,
        status: "idle",
      };
      this.broadcast();
      return this.state;
    }

    if (this.runPromise) {
      this.currentSession.requestStop();
      this.state = {
        ...this.state,
        snapshot: this.currentSession.snapshot(),
      };
      this.broadcast();
      return this.state;
    }

    await this.currentSession.clearStage();
    this.currentSession = undefined;
    this.currentTimeline = undefined;
    this.state = {
      ...this.state,
      snapshot: this.state.snapshot
        ? {
            ...this.state.snapshot,
            phase: "created",
            isRecording: false,
          }
        : this.state.snapshot,
      status: "idle",
    };
    this.broadcast();
    return this.state;
  }

  async requestPermissions(): Promise<HudState> {
    if (!this.currentSession) {
      const engine = new MacOSCommandEngine();
      const diagnostics = await engine.requestPermissions();
      this.state = {
        ...this.state,
        engineMode: "macos",
        snapshot: this.withDiagnostics(diagnostics),
      };
      return this.state;
    }

    this.state = {
      ...this.state,
      snapshot: await this.currentSession.requestPermissions(),
    };
    this.broadcast();
    return this.state;
  }

  async openPermissionSettings(kind: "accessibility" | "screen-recording"): Promise<HudState> {
    if (!this.currentSession) {
      const engine = new MacOSCommandEngine();
      await engine.openPermissionSettings(kind);
      return this.state;
    }

    this.state = {
      ...this.state,
      snapshot: await this.currentSession.openPermissionSettings(kind),
    };
    this.broadcast();
    return this.state;
  }

  async refreshDiagnostics(): Promise<HudState> {
    if (!this.currentSession) {
      const engine = this.state.engineMode === "macos"
        ? new MacOSCommandEngine()
        : new MockCaptureEngine();
      const diagnostics = await engine.diagnostics();
      this.state = {
        ...this.state,
        snapshot: this.withDiagnostics(diagnostics),
        sceneSteps: [],
      };
      return this.state;
    }

    this.state = {
      ...this.state,
      snapshot: await this.currentSession.refreshDiagnostics(),
    };
    this.broadcast();
    return this.state;
  }

  private async loadScenario(id: string) {
    const path = resolve(process.cwd(), "scenarios", `${id}.json`);
    const raw = await readFile(path, "utf8");
    return parseScenarioDocument(JSON.parse(raw));
  }

  private withDiagnostics(diagnostics: EngineDiagnostics): HudSnapshot {
    if (this.state.snapshot) {
      return {
        ...this.state.snapshot,
        diagnostics,
      };
    }

    return {
      sessionId: "idle",
      state: "created",
      phase: "created",
      elapsedMs: 0,
      isRecording: false,
      diagnostics,
      controls: [
        { control: "start", enabled: true },
        { control: "pause", enabled: false },
        { control: "stop", enabled: false },
        { control: "replay-last-run", enabled: false },
        { control: "quit", enabled: true },
      ],
      logs: [],
      artifacts: [],
      stage: {
        backdrop: "neutral",
      },
    };
  }

  private applyStepEvent(
    steps: HudState["sceneSteps"],
    event: GuidedSessionEvent,
  ): HudState["sceneSteps"] {
    if (!["action.started", "action.completed", "action.failed"].includes(event.type)) {
      return steps;
    }

    const action = (event.payload as { action?: { id?: string; description?: string } }).action;
    const stepId = action?.id;
    const stepTitle = action?.description;
    if (!stepId && !stepTitle) {
      return steps;
    }

    return steps.map((step) => {
      const isMatch = step.id === stepId || step.title === stepTitle;
      if (!isMatch) {
        return step;
      }

      if (event.type === "action.started") {
        return { ...step, status: "active" };
      }

      if (event.type === "action.completed") {
        return { ...step, status: "completed" };
      }

      return { ...step, status: "failed" };
    });
  }

  addListener(res: ServerResponse): void {
    this.listeners.add(res);
  }

  removeListener(res: ServerResponse): void {
    this.listeners.delete(res);
  }

  private async pushSnapshot(): Promise<void> {
    if (!this.currentSession) {
      return;
    }

    this.state = {
      ...this.state,
      snapshot: this.currentSession.snapshot(),
    };
    this.broadcast();
  }

  private broadcast(): void {
    const payload = `data: ${JSON.stringify(this.state)}\n\n`;

    for (const listener of this.listeners) {
      listener.write(payload);
    }
  }

  private async pollStageControls(): Promise<void> {
    if (!this.currentSession || this.state.engineMode !== "macos") {
      return;
    }
    const session = this.currentSession;

    const commands = await session.consumeStageControls();
    if (commands.length === 0) {
      return;
    }

    for (const command of commands) {
      switch (command) {
        case "start":
          if (this.state.status === "staged") {
            void this.run();
          } else {
            void this.start(this.state.engineMode);
          }
          break;
        case "stop":
          if (this.state.status === "running") {
            session.requestStop();
            this.state = {
              ...this.state,
              snapshot: session.snapshot(),
            };
            this.broadcast();
          }
          break;
        case "replay":
          void this.replay();
          break;
        case "clear":
        case "quit":
          await this.clear();
          break;
        default:
          break;
      }
    }
  }
}

const controller = new HudController();

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
  });
  res.end(JSON.stringify(body));
}

function contentType(path: string): string {
  switch (extname(path).toLowerCase()) {
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".mov":
      return "video/quicktime";
    case ".json":
      return "application/json; charset=utf-8";
    default:
      return "application/octet-stream";
  }
}

function html(): string {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Action HUD</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
      :root {
        --bg: #0a0a0b;
        --panel: rgba(14, 14, 16, 0.92);
        --ink: #e6e6e8;
        --muted: #9a9aa1;
        --line: rgba(255, 255, 255, 0.16);
        --line-soft: rgba(255, 255, 255, 0.08);
        --success: #d4d4d8;
        --error: #ef4444;
        --shadow: 0 20px 48px rgba(0, 0, 0, 0.42);
        --radius-lg: 8px;
        --radius-md: 4px;
        --radius-sm: 2px;
      }

      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: "IBM Plex Mono", monospace;
        color: var(--ink);
        background:
          radial-gradient(circle at 12% 10%, rgba(255,255,255,0.08), transparent 26%),
          radial-gradient(circle at 90% 80%, rgba(255,255,255,0.06), transparent 24%),
          linear-gradient(140deg, #050505 0%, #0c0c0e 100%);
      }

      .shell {
        display: grid;
        grid-template-columns: 1.3fr 0.7fr;
        gap: 14px;
        padding: 14px;
      }

      .hero, .panel {
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: var(--radius-lg);
        box-shadow: var(--shadow);
        backdrop-filter: blur(10px);
      }

      .hero {
        min-height: calc(100vh - 48px);
        padding: 18px;
        position: relative;
        overflow: hidden;
      }

      .hero::before {
        content: "";
        position: absolute;
        inset: 12px;
        border: 1px dashed rgba(255,255,255,0.12);
        border-radius: var(--radius-md);
        pointer-events: none;
      }

      .eyebrow {
        font-size: 12px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--muted);
      }

      h1 {
        font-size: clamp(2rem, 4vw, 3.4rem);
        line-height: 1.02;
        margin: 12px 0 18px;
        max-width: 16ch;
      }

      .lede {
        max-width: 44ch;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.7;
      }

      .viewport {
        margin-top: 18px;
        background: linear-gradient(160deg, #121214, #0b0b0d);
        color: #f3f4f6;
        border-radius: var(--radius-md);
        min-height: 380px;
        padding: 14px;
        position: relative;
        overflow: hidden;
      }

      .viewport::after {
        content: "";
        position: absolute;
        inset: 12px;
        border: 1px solid rgba(255,255,255,0.14);
        border-radius: var(--radius-sm);
        pointer-events: none;
      }

      .status-row {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 20px;
      }

      .timer {
        margin-left: auto;
        padding: 10px 14px;
        border-radius: var(--radius-sm);
        background: rgba(255,255,255,0.1);
        border: 1px solid rgba(255,255,255,0.14);
      }

      .record-start {
        margin-top: 10px;
        padding: 8px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--line-soft);
        background: rgba(255,255,255,0.04);
        color: var(--muted);
        font-size: 12px;
      }

      .status {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 10px 14px;
        border-radius: var(--radius-sm);
        background: rgba(255,255,255,0.08);
        border: 1px solid rgba(255,255,255,0.12);
        font-size: 13px;
      }

      .status strong { color: #f3f4f6; }

      .stack {
        display: grid;
        gap: 18px;
      }

      .stage-meta {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 12px;
        margin-top: 18px;
      }

      .stage-card {
        padding: 14px;
        border-radius: var(--radius-sm);
        background: rgba(255,255,255,0.06);
        border: 1px solid rgba(255,255,255,0.1);
      }

      .stage-card strong {
        display: block;
        margin-top: 8px;
        color: #f3f4f6;
        font-size: 1rem;
      }

      .stage-canvas {
        position: relative;
        margin-top: 22px;
        aspect-ratio: 16 / 10;
        border-radius: var(--radius-md);
        overflow: hidden;
        background:
          radial-gradient(circle at 20% 18%, rgba(255, 255, 255, 0.12), transparent 30%),
          linear-gradient(140deg, #121214 0%, #0f0f11 58%, #101215 100%);
        box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08);
      }

      .stage-canvas[data-backdrop="studio"] {
        background:
          radial-gradient(circle at 18% 18%, rgba(255, 255, 255, 0.1), transparent 30%),
          radial-gradient(circle at 80% 84%, rgba(255, 255, 255, 0.08), transparent 24%),
          linear-gradient(140deg, #141417 0%, #101012 58%, #101215 100%);
      }

      .stage-canvas[data-backdrop="gradient"] {
        background:
          radial-gradient(circle at 20% 18%, rgba(255, 255, 255, 0.1), transparent 30%),
          linear-gradient(145deg, #1a1a1d 0%, #121215 52%, #0d0d10 100%);
      }

      .stage-canvas[data-backdrop="spotlight"] {
        background:
          radial-gradient(circle at 50% 50%, rgba(255, 255, 255, 0.14), transparent 18%),
          linear-gradient(145deg, #171717 0%, #101214 100%);
      }

      .viewport-frame {
        position: absolute;
        left: var(--viewport-left, 18%);
        top: var(--viewport-top, 15%);
        width: var(--viewport-width, 64%);
        height: var(--viewport-height, 70%);
        border-radius: var(--radius-sm);
        overflow: hidden;
        background: rgba(255,255,255,0.04);
        border: 1px solid rgba(255,255,255,0.18);
        box-shadow:
          0 24px 90px rgba(0,0,0,0.44),
          0 0 0 1px rgba(255,255,255,0.08) inset;
      }

      .viewport-frame[data-active="true"] {
        border-color: rgba(255, 255, 255, 0.7);
        box-shadow:
          0 24px 90px rgba(0,0,0,0.44),
          0 0 0 1px rgba(255,255,255,0.08) inset,
          0 0 0 3px rgba(255, 255, 255, 0.15);
      }

      .viewport-mask {
        position: absolute;
        background: rgba(7, 7, 9, 0.56);
        transition: opacity 160ms ease;
        opacity: 0;
        pointer-events: none;
      }

      .stage-canvas[data-dimmed="true"] .viewport-mask {
        opacity: 1;
      }

      .mask-top {
        left: 0;
        top: 0;
        width: 100%;
        height: var(--viewport-top, 15%);
      }

      .mask-bottom {
        left: 0;
        top: calc(var(--viewport-top, 15%) + var(--viewport-height, 70%));
        width: 100%;
        bottom: 0;
      }

      .mask-left {
        left: 0;
        top: var(--viewport-top, 15%);
        width: var(--viewport-left, 18%);
        height: var(--viewport-height, 70%);
      }

      .mask-right {
        right: 0;
        top: var(--viewport-top, 15%);
        width: calc(100% - var(--viewport-left, 18%) - var(--viewport-width, 64%));
        height: var(--viewport-height, 70%);
      }

      .recording-pill {
        position: absolute;
        top: 18px;
        right: 18px;
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 10px 14px;
        border-radius: var(--radius-sm);
        background: rgba(8, 8, 10, 0.72);
        border: 1px solid rgba(255,255,255,0.14);
        color: white;
        z-index: 2;
      }

      .recording-pill[hidden] {
        display: none;
      }

      .record-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: #f5f5f5;
        box-shadow: 0 0 0 8px rgba(255, 255, 255, 0.16);
      }

      .countdown {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        font-family: "IBM Plex Mono", monospace;
        font-size: clamp(5rem, 12vw, 10rem);
        line-height: 1;
        color: rgba(245, 245, 245, 0.94);
        text-shadow: 0 18px 60px rgba(0,0,0,0.45);
        z-index: 2;
      }

      .countdown[hidden] {
        display: none;
      }

      .window-skin {
        position: absolute;
        inset: 0;
        display: grid;
        grid-template-rows: 48px 1fr;
        background: linear-gradient(180deg, rgba(34,34,38,0.92), rgba(14,14,16,0.96));
      }

      .window-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 18px;
        border-bottom: 1px solid rgba(255,255,255,0.08);
        background: rgba(255,255,255,0.04);
      }

      .traffic {
        display: inline-flex;
        gap: 8px;
      }

      .traffic span {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: rgba(255,255,255,0.18);
      }

      .traffic span:nth-child(1) { background: rgba(255,255,255,0.42); }
      .traffic span:nth-child(2) { background: rgba(255,255,255,0.26); }
      .traffic span:nth-child(3) { background: rgba(255,255,255,0.18); }

      .window-title {
        color: rgba(255,255,255,0.88);
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .window-body {
        position: relative;
        overflow: hidden;
      }

      .window-body img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .window-placeholder {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        padding: 28px;
        color: rgba(255,255,255,0.85);
        text-align: center;
        background:
          radial-gradient(circle at top, rgba(255,255,255,0.06), transparent 36%),
          linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0));
      }

      .window-placeholder strong {
        display: block;
        font-size: clamp(1.5rem, 4vw, 2.4rem);
        margin-bottom: 10px;
      }

      .window-placeholder small {
        display: block;
        max-width: 30ch;
        color: rgba(255,255,255,0.64);
        line-height: 1.6;
      }

      .panel {
        padding: 18px;
      }

      .section-title {
        font-size: 1.2rem;
        margin: 0 0 14px;
      }

      .grid {
        display: grid;
        gap: 14px;
      }

      .controls {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
      }

      button {
        border: 0;
        border-radius: var(--radius-sm);
        padding: 14px 16px;
        font-size: 14px;
        cursor: pointer;
        background: #f3f4f6;
        color: #09090b;
        transition: transform 140ms ease, opacity 140ms ease, background 140ms ease;
      }

      button.secondary {
        background: rgba(255,255,255,0.04);
        color: var(--ink);
        border: 1px solid var(--line-soft);
      }

      button:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }

      button:not(:disabled):hover { transform: translateY(-1px); }

      .diagnostics, .artifacts, .logs, .steps {
        display: grid;
        gap: 10px;
      }

      .chip {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        background: rgba(255,255,255,0.08);
        color: var(--ink);
      }

      .chip[data-state="granted"] { background: rgba(255,255,255,0.12); color: var(--success); }
      .chip[data-state="denied"] { background: rgba(143, 29, 44, 0.12); color: var(--error); }
      .chip[data-state="unknown"] { background: rgba(17, 17, 17, 0.06); color: var(--muted); }

      .list {
        display: grid;
        gap: 10px;
        max-height: 320px;
        overflow: auto;
        padding-right: 4px;
      }

      .log {
        padding: 12px;
        border-radius: var(--radius-sm);
        background: rgba(17,17,17,0.04);
        border: 1px solid rgba(17,17,17,0.06);
      }

      .log small, .artifact small, .meta {
        color: var(--muted);
      }

      .artifact {
        padding: 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--line);
        background: rgba(255,255,255,0.04);
      }

      .artifact a {
        color: inherit;
        text-decoration: none;
      }

      .meta {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        font-size: 12px;
      }

      .step {
        display: grid;
        grid-template-columns: 22px 1fr;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background: rgba(255,255,255,0.03);
        border: 1px solid var(--line-soft);
      }

      .step-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: rgba(255,255,255,0.35);
        box-shadow: 0 0 0 6px rgba(255,255,255,0.05);
      }

      .step[data-status="active"] .step-dot {
        background: #f5f5f5;
      }

      .step[data-status="completed"] .step-dot {
        background: #9ca3af;
      }

      .step[data-status="failed"] .step-dot {
        background: #ef4444;
      }

      .step small {
        color: var(--muted);
      }

      @media (max-width: 980px) {
        .shell {
          grid-template-columns: 1fr;
        }

        .hero {
          min-height: auto;
        }

        .stage-meta {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </head>
  <body>
    <div class="shell">
      <section class="hero">
        <div class="eyebrow">Action / Guided Capture</div>
        <h1>Operator HUD</h1>
        <p class="lede">A dev-facing control surface for the first milestone. It shows live session state, permissions, artifacts, and a Calculator scenario run while the native macOS host catches up.</p>
        <div class="viewport">
          <div class="eyebrow">Current Session</div>
          <div class="status-row">
            <div class="status"><span>Mode</span><strong id="mode">mock</strong></div>
            <div class="status"><span>Status</span><strong id="status">idle</strong></div>
            <div class="status"><span>Phase</span><strong id="phase">created</strong></div>
            <div class="status"><span>Target</span><strong id="target">Calculator</strong></div>
            <div class="timer"><strong id="timer">00:00.0</strong></div>
          </div>
          <div class="record-start" id="record-start">Recording timer idle</div>
          <div class="stage-meta">
            <div class="stage-card">
              <small>Backdrop</small>
              <strong id="backdrop">studio</strong>
            </div>
            <div class="stage-card">
              <small>Viewport</small>
              <strong id="viewport-bounds">320,180 960x720</strong>
            </div>
            <div class="stage-card">
              <small>Capture</small>
              <strong id="capture-state">idle</strong>
            </div>
          </div>
          <div class="stage-canvas" id="stage-canvas" data-backdrop="studio" data-dimmed="false">
            <div class="recording-pill" id="recording-pill" hidden>
              <span class="record-dot"></span>
              <span id="recording-label">Recording</span>
            </div>
            <div class="countdown" id="countdown" hidden>3</div>
            <div class="viewport-mask mask-top"></div>
            <div class="viewport-mask mask-bottom"></div>
            <div class="viewport-mask mask-left"></div>
            <div class="viewport-mask mask-right"></div>
            <div class="viewport-frame" id="viewport-frame" data-active="false">
              <div class="window-skin">
                <div class="window-bar">
                  <div class="traffic"><span></span><span></span><span></span></div>
                  <div class="window-title" id="window-title">Calculator</div>
                  <div class="eyebrow" id="window-phase">Staging</div>
                </div>
                <div class="window-body">
                  <img id="screenshot-preview" alt="Latest viewport screenshot" hidden />
                  <div class="window-placeholder" id="window-placeholder">
                    <div>
                      <strong id="placeholder-target">Calculator</strong>
                      <small id="placeholder-copy">Stage the target app, count into recording, and keep the viewport crisp while artifacts and logs update on the side.</small>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
      <aside class="stack">
        <section class="panel">
          <h2 class="section-title">Controls</h2>
          <div class="controls">
            <button id="stage-mock">Stage Mock Scene</button>
            <button id="stage-macos" class="secondary">Stage macOS Scene</button>
            <button id="run-scene">Run Staged Scene</button>
            <button id="clear-scene" class="secondary">Clear Stage</button>
            <button id="request-perms" class="secondary">Request Permissions</button>
            <button id="open-access" class="secondary">Open Accessibility</button>
            <button id="open-screen" class="secondary">Open Screen Recording</button>
            <button id="replay" class="secondary">Replay Last Run</button>
            <button id="refresh" class="secondary">Refresh State</button>
          </div>
        </section>
        <section class="panel">
          <h2 class="section-title">Permissions</h2>
          <div class="diagnostics">
            <div class="chip" id="access-chip" data-state="unknown">Accessibility: unknown</div>
            <div class="chip" id="screen-chip" data-state="unknown">Screen Recording: unknown</div>
            <div class="notes list" id="diagnostic-notes"></div>
            <div class="meta" id="error"></div>
          </div>
        </section>
        <section class="panel">
          <h2 class="section-title">Artifacts</h2>
          <div class="artifacts list" id="artifacts"></div>
        </section>
        <section class="panel">
          <h2 class="section-title">Scene Steps</h2>
          <div class="steps list" id="steps"></div>
        </section>
        <section class="panel">
          <h2 class="section-title">Logs</h2>
          <div class="logs list" id="logs"></div>
        </section>
      </aside>
    </div>
    <script>
      const els = {
        mode: document.getElementById("mode"),
        status: document.getElementById("status"),
        phase: document.getElementById("phase"),
        target: document.getElementById("target"),
        timer: document.getElementById("timer"),
        recordStart: document.getElementById("record-start"),
        backdrop: document.getElementById("backdrop"),
        viewportBounds: document.getElementById("viewport-bounds"),
        captureState: document.getElementById("capture-state"),
        stageCanvas: document.getElementById("stage-canvas"),
        viewportFrame: document.getElementById("viewport-frame"),
        recordingPill: document.getElementById("recording-pill"),
        recordingLabel: document.getElementById("recording-label"),
        countdown: document.getElementById("countdown"),
        windowTitle: document.getElementById("window-title"),
        windowPhase: document.getElementById("window-phase"),
        screenshotPreview: document.getElementById("screenshot-preview"),
        windowPlaceholder: document.getElementById("window-placeholder"),
        placeholderTarget: document.getElementById("placeholder-target"),
        access: document.getElementById("access-chip"),
        screen: document.getElementById("screen-chip"),
        notes: document.getElementById("diagnostic-notes"),
        error: document.getElementById("error"),
        artifacts: document.getElementById("artifacts"),
        steps: document.getElementById("steps"),
        logs: document.getElementById("logs")
      };

      let lastPreviewPath = "";

      async function post(path) {
        await fetch(path, { method: "POST" });
      }

      function setChip(el, label, state) {
        el.dataset.state = state || "unknown";
        el.textContent = label + ": " + (state || "unknown");
      }

      function formatElapsed(ms) {
        const totalSeconds = Math.max(ms || 0, 0) / 1000;
        const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, "0");
        const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, "0");
        const tenths = Math.floor((totalSeconds % 1) * 10).toString();
        return minutes + ":" + seconds + "." + tenths;
      }

      function updateStageLayout(viewport) {
        if (!viewport || !viewport.bounds) {
          els.viewportFrame.style.removeProperty("--viewport-left");
          els.viewportFrame.style.removeProperty("--viewport-top");
          els.viewportFrame.style.removeProperty("--viewport-width");
          els.viewportFrame.style.removeProperty("--viewport-height");
          els.stageCanvas.style.removeProperty("--viewport-left");
          els.stageCanvas.style.removeProperty("--viewport-top");
          els.stageCanvas.style.removeProperty("--viewport-width");
          els.stageCanvas.style.removeProperty("--viewport-height");
          return;
        }

        const bounds = viewport.bounds;
        const stageWidth = bounds.width + 320;
        const stageHeight = bounds.height + 220;
        const left = ((stageWidth - bounds.width) / 2 / stageWidth) * 100;
        const top = ((stageHeight - bounds.height) / 2 / stageHeight) * 100;
        const width = (bounds.width / stageWidth) * 100;
        const height = (bounds.height / stageHeight) * 100;

        for (const el of [els.viewportFrame, els.stageCanvas]) {
          el.style.setProperty("--viewport-left", left.toFixed(2) + "%");
          el.style.setProperty("--viewport-top", top.toFixed(2) + "%");
          el.style.setProperty("--viewport-width", width.toFixed(2) + "%");
          el.style.setProperty("--viewport-height", height.toFixed(2) + "%");
        }
      }

      function latestCountdown(state) {
        const tick = [...(state.events || [])].reverse().find((event) => event.type === "countdown.tick");
        return tick && tick.payload ? tick.payload.remaining : null;
      }

      function render(state) {
        const snapshot = state.snapshot || {};
        const phase = snapshot.phase || "created";
        const viewport = snapshot.stage && snapshot.stage.viewport;
        const screenshot = [...(snapshot.artifacts || [])].reverse().find((artifact) => artifact.kind === "screenshot");

        els.mode.textContent = state.engineMode;
        els.status.textContent = state.status;
        els.phase.textContent = phase;
        els.target.textContent = snapshot.targetApp || "Calculator";
        els.timer.textContent = formatElapsed(snapshot.elapsedMs || 0);
        els.backdrop.textContent = snapshot.stage?.backdrop || "neutral";
        els.captureState.textContent = snapshot.isRecording ? "recording" : phase;
        els.windowTitle.textContent = snapshot.targetApp || "Calculator";
        els.windowPhase.textContent = phase;
        els.placeholderTarget.textContent = snapshot.targetApp || "Calculator";
        setChip(els.access, "Accessibility", snapshot.diagnostics?.accessibility);
        setChip(els.screen, "Screen Recording", snapshot.diagnostics?.screenRecording);
        els.stageCanvas.dataset.backdrop = snapshot.stage?.backdrop || "neutral";
        els.stageCanvas.dataset.dimmed = (phase === "countdown" || snapshot.isRecording) ? "true" : "false";
        els.viewportFrame.dataset.active = snapshot.isRecording ? "true" : "false";
        els.recordingPill.hidden = !(snapshot.isRecording || phase === "paused" || phase === "completing");
        els.recordingLabel.textContent = phase === "paused" ? "Paused" : "Recording";
        const countdown = latestCountdown(state);
        els.countdown.hidden = phase !== "countdown";
        els.countdown.textContent = countdown ? String(countdown) : "";
        if (phase === "countdown" && countdown) {
          els.recordStart.textContent = "Recording starts in " + countdown + "s";
        } else if (snapshot.isRecording) {
          els.recordStart.textContent = "Recording live";
        } else if (phase === "completed") {
          els.recordStart.textContent = "Completed. Review the captured artifacts.";
        } else {
          els.recordStart.textContent = "Recording timer idle";
        }
        updateStageLayout(viewport);
        els.viewportBounds.textContent = viewport
          ? viewport.bounds.x + "," + viewport.bounds.y + " " + viewport.bounds.width + "x" + viewport.bounds.height
          : "not set";

        if (screenshot && screenshot.path !== lastPreviewPath) {
          els.screenshotPreview.src = "/api/file?path=" + encodeURIComponent(screenshot.path) + "&v=" + Date.now();
          lastPreviewPath = screenshot.path;
        }

        const hasScreenshot = Boolean(screenshot);
        els.screenshotPreview.hidden = !hasScreenshot;
        els.windowPlaceholder.hidden = hasScreenshot;

        els.notes.innerHTML = "";
        for (const note of snapshot.diagnostics?.notes || []) {
          const node = document.createElement("div");
          node.className = "artifact";
          node.innerHTML = "<small>" + note + "</small>";
          els.notes.appendChild(node);
        }
        els.error.textContent = state.error || "";

        els.artifacts.innerHTML = "";
        for (const artifact of snapshot.artifacts || []) {
          const node = document.createElement("div");
          node.className = "artifact";
          node.innerHTML = "<a href='/api/file?path=" + encodeURIComponent(artifact.path) + "' target='_blank' rel='noreferrer'><strong>" + artifact.kind + "</strong><br><small>" + artifact.path + "</small></a>";
          els.artifacts.appendChild(node);
        }

        els.steps.innerHTML = "";
        for (const [index, step] of (state.sceneSteps || []).entries()) {
          const node = document.createElement("div");
          node.className = "step";
          node.dataset.status = step.status;
          node.innerHTML = "<span class='step-dot'></span><div><strong>" + (index + 1) + ". " + step.title + "</strong><br><small>" + step.status + "</small></div>";
          els.steps.appendChild(node);
        }

        els.logs.innerHTML = "";
        for (const log of snapshot.logs || []) {
          const node = document.createElement("div");
          node.className = "log";
          node.innerHTML = "<div><strong>" + log.message + "</strong></div><div class='meta'><span>" + log.eventType + "</span><span>" + new Date(log.at).toLocaleTimeString() + "</span></div>";
          els.logs.appendChild(node);
        }
      }

      document.getElementById("stage-mock").onclick = () => post("/api/stage?engine=mock");
      document.getElementById("stage-macos").onclick = () => post("/api/stage?engine=macos");
      document.getElementById("run-scene").onclick = () => post("/api/run");
      document.getElementById("clear-scene").onclick = () => post("/api/clear");
      document.getElementById("request-perms").onclick = () => post("/api/permissions/request");
      document.getElementById("open-access").onclick = () => post("/api/permissions/open?kind=accessibility");
      document.getElementById("open-screen").onclick = () => post("/api/permissions/open?kind=screen-recording");
      document.getElementById("replay").onclick = () => post("/api/replay");
      document.getElementById("refresh").onclick = async () => {
        const state = await fetch("/api/diagnostics/refresh", { method: "POST" }).then((res) => res.json());
        render(state);
      };

      fetch("/api/state").then((res) => res.json()).then(render);
      const source = new EventSource("/api/events");
      source.onmessage = (event) => render(JSON.parse(event.data));
    </script>
  </body>
</html>`;
}

async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const url = new URL(req.url ?? "/", "http://localhost:4318");

  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(html());
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/state") {
    sendJson(res, 200, controller.getState());
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/file") {
    const path = url.searchParams.get("path");
    const artifactsRoot = resolve(process.cwd(), "artifacts");

    if (!path) {
      sendJson(res, 400, { error: "Missing file path" });
      return;
    }

    const resolvedPath = resolve(path);
    if (!resolvedPath.startsWith(artifactsRoot)) {
      sendJson(res, 403, { error: "Only artifact files can be served" });
      return;
    }

    try {
      const data = await readFile(resolvedPath);
      res.writeHead(200, { "content-type": contentType(resolvedPath) });
      res.end(data);
    } catch (error) {
      sendJson(res, 404, {
        error: error instanceof Error ? error.message : "Artifact not found",
      });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/events") {
    res.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    });
    res.write(`data: ${JSON.stringify(controller.getState())}\n\n`);
    controller.addListener(res);
    req.on("close", () => controller.removeListener(res));
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/start") {
    const engine = url.searchParams.get("engine") === "macos" ? "macos" : "mock";
    sendJson(res, 200, await controller.start(engine));
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/stage") {
    const engine = url.searchParams.get("engine") === "macos" ? "macos" : "mock";
    sendJson(res, 200, await controller.stage(engine));
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/run") {
    sendJson(res, 200, await controller.run());
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/replay") {
    sendJson(res, 200, await controller.replay());
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/clear") {
    sendJson(res, 200, await controller.clear());
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/permissions/request") {
    sendJson(res, 200, await controller.requestPermissions());
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/permissions/open") {
    const kind = url.searchParams.get("kind") === "screen-recording"
      ? "screen-recording"
      : "accessibility";
    sendJson(res, 200, await controller.openPermissionSettings(kind));
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/diagnostics/refresh") {
    sendJson(res, 200, await controller.refreshDiagnostics());
    return;
  }

  sendJson(res, 404, { error: "Not found" });
}

createServer((req, res) => {
  void handle(req, res);
}).listen(4318, () => {
  process.stdout.write("Action HUD listening on http://localhost:4318\n");
});
