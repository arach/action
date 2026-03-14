import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { compileScenario, parseScenarioDocument } from "@action/compiler";
import type { EngineDiagnostics, GuidedSessionEvent, HudSnapshot } from "@action/protocol";
import { GuidedCaptureSession, MacOSCommandEngine, MockCaptureEngine } from "@action/runtime";

type EngineMode = "mock" | "macos";

interface HudState {
  engineMode: EngineMode;
  snapshot?: HudSnapshot;
  events: GuidedSessionEvent[];
  status: "idle" | "running" | "completed" | "failed";
  error?: string;
}

class HudController {
  private currentSession?: GuidedCaptureSession;
  private readonly listeners = new Set<ServerResponse>();
  private state: HudState = {
    engineMode: "mock",
    events: [],
    status: "idle",
  };

  getState(): HudState {
    return this.state;
  }

  async start(engineMode: EngineMode): Promise<HudState> {
    if (this.state.status === "running") {
      return this.state;
    }

    const scenario = await this.loadScenario("calculator-demo");
    const engine = engineMode === "macos"
      ? new MacOSCommandEngine()
      : new MockCaptureEngine();

    const session = new GuidedCaptureSession(engine, {
      sessionId: `session_${scenario.id.replace(/[^a-z0-9]+/gi, "_")}`,
      outputDir: `artifacts/sessions/${scenario.id}`,
    });

    this.currentSession = session;
    this.state = {
      engineMode,
      snapshot: session.snapshot(),
      events: [],
      status: "running",
    };

    session.onEvent((event) => {
      this.state = {
        ...this.state,
        snapshot: session.snapshot(),
        events: [...this.state.events, event],
      };
      this.broadcast();
    });

    const { timeline } = compileScenario(scenario);

    void (async () => {
      try {
        await session.stageScene({
          backdrop: scenario.stage.backdrop,
          viewport: scenario.stage.viewport,
          targetApp: scenario.targetApp,
        });
        await this.pushSnapshot();

        await session.beginRun(timeline);
        await this.pushSnapshot();

        await session.captureScreenshot();
        await this.pushSnapshot();

        await session.stop();
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
      }

      this.broadcast();
    })();

    this.broadcast();
    return this.state;
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
}

const controller = new HudController();

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
  });
  res.end(JSON.stringify(body));
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
    <link href="https://fonts.googleapis.com/css2?family=Syne:wght@500;700;800&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
      :root {
        --bg: #f4efe7;
        --panel: rgba(255, 251, 245, 0.85);
        --ink: #111111;
        --muted: #5a564f;
        --accent: #ff6a00;
        --accent-soft: rgba(255, 106, 0, 0.14);
        --line: rgba(17, 17, 17, 0.1);
        --success: #11795b;
        --warn: #8a4b00;
        --error: #8f1d2c;
        --shadow: 0 24px 80px rgba(30, 18, 4, 0.16);
      }

      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: "IBM Plex Mono", monospace;
        color: var(--ink);
        background:
          radial-gradient(circle at top left, rgba(255,106,0,0.24), transparent 34%),
          linear-gradient(135deg, #fbf6ee 0%, #efe7db 100%);
      }

      .shell {
        display: grid;
        grid-template-columns: 1.2fr 0.8fr;
        gap: 24px;
        padding: 24px;
      }

      .hero, .panel {
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: 28px;
        box-shadow: var(--shadow);
        backdrop-filter: blur(18px);
      }

      .hero {
        min-height: calc(100vh - 48px);
        padding: 28px;
        position: relative;
        overflow: hidden;
      }

      .hero::before {
        content: "";
        position: absolute;
        inset: 18px;
        border: 1px dashed rgba(17,17,17,0.12);
        border-radius: 24px;
        pointer-events: none;
      }

      .eyebrow, h1, .status, .section-title, button {
        font-family: "Syne", sans-serif;
      }

      .eyebrow {
        font-size: 12px;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--muted);
      }

      h1 {
        font-size: clamp(3rem, 6vw, 6rem);
        line-height: 0.92;
        margin: 12px 0 18px;
        max-width: 8ch;
      }

      .lede {
        max-width: 44ch;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.7;
      }

      .viewport {
        margin-top: 32px;
        background: linear-gradient(160deg, #141414, #292119);
        color: #f6ead7;
        border-radius: 24px;
        min-height: 420px;
        padding: 22px;
        position: relative;
        overflow: hidden;
      }

      .viewport::after {
        content: "";
        position: absolute;
        inset: 20px;
        border: 1px solid rgba(246,234,215,0.18);
        border-radius: 18px;
        pointer-events: none;
      }

      .status-row {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 20px;
      }

      .status {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 10px 14px;
        border-radius: 999px;
        background: rgba(255,255,255,0.08);
        border: 1px solid rgba(255,255,255,0.12);
        font-size: 13px;
      }

      .status strong { color: white; }

      .stack {
        display: grid;
        gap: 18px;
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
        border-radius: 18px;
        padding: 14px 16px;
        font-size: 14px;
        cursor: pointer;
        background: #111111;
        color: white;
        transition: transform 140ms ease, opacity 140ms ease, background 140ms ease;
      }

      button.secondary {
        background: white;
        color: var(--ink);
        border: 1px solid var(--line);
      }

      button:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }

      button:not(:disabled):hover { transform: translateY(-1px); }

      .diagnostics, .artifacts, .logs {
        display: grid;
        gap: 10px;
      }

      .chip {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: 999px;
        background: var(--accent-soft);
        color: var(--ink);
      }

      .chip[data-state="granted"] { background: rgba(17, 121, 91, 0.12); color: var(--success); }
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
        border-radius: 16px;
        background: rgba(17,17,17,0.04);
        border: 1px solid rgba(17,17,17,0.06);
      }

      .log small, .artifact small, .meta {
        color: var(--muted);
      }

      .artifact {
        padding: 12px;
        border-radius: 16px;
        border: 1px solid var(--line);
        background: rgba(255,255,255,0.65);
      }

      .meta {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        font-size: 12px;
      }

      @media (max-width: 980px) {
        .shell {
          grid-template-columns: 1fr;
        }

        .hero {
          min-height: auto;
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
          </div>
        </div>
      </section>
      <aside class="stack">
        <section class="panel">
          <h2 class="section-title">Controls</h2>
          <div class="controls">
            <button id="start-mock">Run Mock Demo</button>
            <button id="start-macos" class="secondary">Run macOS Demo</button>
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
        access: document.getElementById("access-chip"),
        screen: document.getElementById("screen-chip"),
        notes: document.getElementById("diagnostic-notes"),
        error: document.getElementById("error"),
        artifacts: document.getElementById("artifacts"),
        logs: document.getElementById("logs")
      };

      async function post(path) {
        await fetch(path, { method: "POST" });
      }

      function setChip(el, label, state) {
        el.dataset.state = state || "unknown";
        el.textContent = label + ": " + (state || "unknown");
      }

      function render(state) {
        els.mode.textContent = state.engineMode;
        els.status.textContent = state.status;
        els.phase.textContent = state.snapshot?.phase || "created";
        els.target.textContent = state.snapshot?.targetApp || "Calculator";
        setChip(els.access, "Accessibility", state.snapshot?.diagnostics?.accessibility);
        setChip(els.screen, "Screen Recording", state.snapshot?.diagnostics?.screenRecording);
        els.notes.innerHTML = "";
        for (const note of state.snapshot?.diagnostics?.notes || []) {
          const node = document.createElement("div");
          node.className = "artifact";
          node.innerHTML = "<small>" + note + "</small>";
          els.notes.appendChild(node);
        }
        els.error.textContent = state.error || "";

        els.artifacts.innerHTML = "";
        for (const artifact of state.snapshot?.artifacts || []) {
          const node = document.createElement("div");
          node.className = "artifact";
          node.innerHTML = "<strong>" + artifact.kind + "</strong><br><small>" + artifact.path + "</small>";
          els.artifacts.appendChild(node);
        }

        els.logs.innerHTML = "";
        for (const log of state.snapshot?.logs || []) {
          const node = document.createElement("div");
          node.className = "log";
          node.innerHTML = "<div><strong>" + log.message + "</strong></div><div class='meta'><span>" + log.eventType + "</span><span>" + new Date(log.at).toLocaleTimeString() + "</span></div>";
          els.logs.appendChild(node);
        }
      }

      document.getElementById("start-mock").onclick = () => post("/api/start?engine=mock");
      document.getElementById("start-macos").onclick = () => post("/api/start?engine=macos");
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

  if (req.method === "POST" && url.pathname === "/api/replay") {
    sendJson(res, 200, await controller.replay());
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
