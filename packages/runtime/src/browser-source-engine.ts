import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type {
  BackdropPreset,
  Bounds,
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

import { MacOSCommandEngine } from "./macos.js";

const execFileAsync = promisify(execFile);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function stringValue(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 ? input : undefined;
}

function numberValue(input: unknown): number | undefined {
  return typeof input === "number" && Number.isFinite(input) ? input : undefined;
}

function booleanValue(input: unknown): boolean {
  return input === true || input === "true";
}

function normalizeBrowserRole(role: string | undefined): string | undefined {
  if (!role) {
    return undefined;
  }

  return role
    .replace(/^AX/, "")
    .replace(/([a-z])([A-Z])/g, "$1-$2")
    .toLowerCase();
}

function keySequence(action: RuntimeAction): string {
  const keys = Array.isArray(action.input?.keys)
    ? action.input.keys.filter((value): value is string => typeof value === "string" && value.length > 0)
    : [];
  const modifiers = Array.isArray(action.input?.modifiers)
    ? action.input.modifiers.filter((value): value is string => typeof value === "string" && value.length > 0)
    : [];
  const key = stringValue(action.input?.key) ?? keys.at(-1) ?? "";
  const prefix = keys.length > 1 ? keys.slice(0, -1) : modifiers;

  return [...prefix, key].filter(Boolean).join("+");
}

export interface BrowserSourceEngineOptions {
  url: string;
  sessionName: string;
  cwd?: string;
  viewport?: Bounds;
  nativeHostPath?: string;
}

export class BrowserSourceEngine implements CaptureEngine {
  private readonly native: MacOSCommandEngine;
  private currentSurfaceId?: string;

  constructor(private readonly options: BrowserSourceEngineOptions) {
    this.native = new MacOSCommandEngine(options.nativeHostPath);
  }

  diagnostics(): Promise<EngineDiagnostics> {
    return this.native.diagnostics();
  }

  requestPermissions(): Promise<EngineDiagnostics> {
    return this.native.requestPermissions();
  }

  openPermissionSettings(kind: "accessibility" | "screen-recording"): Promise<void> {
    return this.native.openPermissionSettings(kind);
  }

  presentStage(presentation: StagePresentation): Promise<void> {
    return this.native.presentStage(presentation);
  }

  clearStage(): Promise<void> {
    return this.native.clearStage();
  }

  setBackdrop(backdrop: BackdropPreset): Promise<void> {
    return this.native.setBackdrop(backdrop);
  }

  async launchApp(app: TargetApp): Promise<SurfaceRef> {
    await this.agentBrowser(["--headed", "open", this.options.url]);
    await this.agentBrowser(["wait", "800"]).catch(() => undefined);
    if (this.options.viewport) {
      await this.agentBrowser([
        "set",
        "viewport",
        String(Math.round(this.options.viewport.width)),
        String(Math.round(this.options.viewport.height)),
      ]).catch(() => undefined);
    }

    const surface = await this.native.launchApp(app);
    this.currentSurfaceId = surface.id;
    return surface;
  }

  focusSurface(surfaceId: string): Promise<void> {
    this.currentSurfaceId = surfaceId;
    return this.native.focusSurface(surfaceId);
  }

  configureViewport(viewport: StageViewport): Promise<StageViewport> {
    return this.native.configureViewport(viewport);
  }

  startCapture(request: {
    sessionId: string;
    outputPath: string;
    viewport?: StageViewport;
    profile?: CaptureProfile;
  }): Promise<void> {
    return this.native.startCapture(request);
  }

  pauseCapture(): Promise<void> {
    return this.native.pauseCapture();
  }

  resumeCapture(): Promise<void> {
    return this.native.resumeCapture();
  }

  stopCapture(): Promise<RuntimeArtifact> {
    return this.native.stopCapture();
  }

  captureScreenshot(path: string): Promise<RuntimeArtifact> {
    return this.native.captureScreenshot(path);
  }

  captureFullScreenshot(path: string): Promise<RuntimeArtifact> {
    return this.native.captureFullScreenshot(path);
  }

  consumeStageControls(): Promise<string[]> {
    return this.native.consumeStageControls();
  }

  async resolveTarget(query: TargetQuery): Promise<ResolvedTarget> {
    return {
      id: query.semanticId ?? query.text ?? "browser-target",
      mode: "dom",
      confidence: 0.9,
      label: query.text ?? query.semanticId ?? "Browser target",
      surfaceId: query.surfaceId ?? this.currentSurfaceId,
    };
  }

  async performAction(action: RuntimeAction): Promise<void> {
    if (action.kind === "click") {
      await this.click(action);
      return;
    }

    if (action.kind === "type") {
      await this.type(action);
      return;
    }

    if (action.kind === "press-key") {
      const key = keySequence(action);
      if (!key) {
        throw new Error("Browser press-key action requires a key");
      }
      await this.agentBrowser(["press", key]);
      return;
    }

    if (action.kind === "wait-for-condition") {
      const durationMs = numberValue(action.input?.durationMs)
        ?? numberValue(action.input?.timeoutMs)
        ?? numberValue(action.input?.ms)
        ?? 800;
      await sleep(durationMs);
      return;
    }

    if (action.kind === "show-cue") {
      return;
    }

    throw new Error(`Browser source driver does not support ${action.kind}`);
  }

  replayArtifact(path: string): Promise<void> {
    return this.native.replayArtifact(path);
  }

  private async click(action: RuntimeAction): Promise<void> {
    const semanticId = action.target?.semanticId;
    if (semanticId?.startsWith("css:")) {
      await this.agentBrowser(["click", semanticId.slice("css:".length)]);
      return;
    }

    const ref = semanticId?.startsWith("ref:") ? semanticId.slice("ref:".length) : undefined;
    if (ref) {
      await this.agentBrowser(["click", ref]);
      return;
    }

    const text = action.target?.text ?? stringValue(action.input?.targetLabel) ?? stringValue(action.input?.label);
    const role = normalizeBrowserRole(action.target?.role ?? stringValue(action.input?.role));
    if (role && text) {
      await this.clickMatchingRole(role, text, {
        allowContains: this.shouldUseFirstMatch(action),
      });
      return;
    }

    if (text) {
      await this.agentBrowser(["find", "text", text, "click"]);
      return;
    }

    if (action.target?.point) {
      await this.agentBrowser([
        "mouse",
        "move",
        String(Math.round(action.target.point.x)),
        String(Math.round(action.target.point.y)),
      ]);
      await this.agentBrowser(["mouse", "down"]);
      await this.agentBrowser(["mouse", "up"]);
      return;
    }

    throw new Error("Browser click action requires text, role, semanticId, or point target");
  }

  private async type(action: RuntimeAction): Promise<void> {
    const text = String(action.input?.text ?? "");
    const semanticId = action.target?.semanticId;
    if (semanticId?.startsWith("css:")) {
      await this.agentBrowser(["fill", semanticId.slice("css:".length), text]);
      return;
    }

    const placeholder = stringValue(action.input?.placeholder);
    if (placeholder) {
      await this.agentBrowser(["find", "placeholder", placeholder, "fill", text]);
      return;
    }

    const label = action.target?.text ?? stringValue(action.input?.label);
    const role = normalizeBrowserRole(action.target?.role ?? stringValue(action.input?.role));
    if (role && label) {
      await this.agentBrowser(["find", "role", role, "fill", text, "--name", label]);
      return;
    }

    if (label) {
      await this.agentBrowser(["find", "label", label, "fill", text]);
      return;
    }

    await this.agentBrowser(["type", "body", text]);
  }

  private async agentBrowser(args: string[]): Promise<string> {
    const { stdout } = await execFileAsync(
      "agent-browser",
      ["--session", this.options.sessionName, ...args],
      {
        cwd: this.options.cwd,
        maxBuffer: 1024 * 1024 * 8,
      },
    );
    return stdout;
  }

  private shouldUseFirstMatch(action: RuntimeAction): boolean {
    return action.input?.match === "first" || booleanValue(action.input?.first);
  }

  private async clickMatchingRole(
    role: string,
    text: string,
    options: { allowContains?: boolean } = {},
  ): Promise<void> {
    const roleSelector = role === "button"
      ? "button,[role='button'],input[type='button'],input[type='submit']"
      : `[role='${role.replace(/'/g, "\\'")}']`;
    const script = `
(() => {
  const expected = ${JSON.stringify(text)}.toLowerCase();
  const allowContains = ${options.allowContains ? "true" : "false"};
  const elements = Array.from(document.querySelectorAll(${JSON.stringify(roleSelector)}));
  const nameFor = (element) => [
    element.textContent,
    element.getAttribute("aria-label"),
    element.getAttribute("title"),
    element.getAttribute("value")
  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
  const target = elements.find((element) => {
    const name = nameFor(element).toLowerCase();
    return name === expected || (allowContains && name.includes(expected));
  });
  if (!target) {
    throw new Error("No matching ${role} named ${text}");
  }
  target.scrollIntoView({ block: "center", inline: "center" });
  target.click();
  return true;
})()
`;
    await this.agentBrowser(["eval", script]);
  }
}
