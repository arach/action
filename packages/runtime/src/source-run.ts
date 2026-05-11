import { compileScenario, type ScenarioDocument } from "@action/compiler";
import type {
  CaptureProfile,
  GuidedSessionEvent,
  HudSnapshot,
} from "@action/protocol";
import { resolve } from "node:path";

import { exportSessionAssets, type SessionAssetExportResult } from "./asset-export.js";
import { GuidedCaptureSession, MockCaptureEngine } from "./guided.js";
import { MacOSCommandEngine } from "./macos.js";

export type SourceRunDriver = "mock" | "macos";

export interface ScenarioSourceRunOptions {
  scenario: ScenarioDocument;
  driver?: SourceRunDriver;
  captureProfile?: CaptureProfile;
  exportAssets?: boolean;
  outputDir?: string;
  root?: string;
}

export interface ScenarioSourceRunResult {
  ok: true;
  kind: "source-run";
  driver: SourceRunDriver;
  profile: CaptureProfile;
  run: {
    snapshot: HudSnapshot;
    events: GuidedSessionEvent[];
    scenario: ScenarioDocument;
    sessionOutputDir: string;
  };
  export?: SessionAssetExportResult;
}

export function scenarioSourceSessionOutputDir(
  scenario: ScenarioDocument,
  root = process.cwd(),
): string {
  return resolve(root, "artifacts", "sessions", scenario.id);
}

export async function runScenarioSource(
  options: ScenarioSourceRunOptions,
): Promise<ScenarioSourceRunResult> {
  const driver = options.driver ?? "mock";
  const profile = options.captureProfile ?? (driver === "macos" ? "final" : "draft");
  const root = options.root ?? process.cwd();

  if (options.exportAssets && driver !== "macos") {
    throw new Error("source run export requires the macos driver because exports verify real media captures");
  }

  const engine = driver === "macos"
    ? new MacOSCommandEngine()
    : new MockCaptureEngine();
  const sessionOutputDir = scenarioSourceSessionOutputDir(options.scenario, root);
  const session = new GuidedCaptureSession(engine, {
    sessionId: `session_${options.scenario.id.replace(/[^a-z0-9]+/gi, "_")}`,
    outputDir: sessionOutputDir,
    captureProfile: profile,
    stageHoldMsAfterComplete: 0,
    initialActionDelayMs: options.scenario.run?.initialActionDelayMs ?? 650,
    actionCadenceMs: options.scenario.run?.actionCadenceMs ?? 900,
  });

  const events: GuidedSessionEvent[] = [];
  session.onEvent((event) => {
    events.push(event);
  });

  await session.stageScene({
    backdrop: options.scenario.stage.backdrop,
    viewport: options.scenario.stage.viewport,
    targetApp: options.scenario.targetApp,
  });

  const { timeline } = compileScenario(options.scenario);

  await session.beginRun(timeline);
  await session.stop();
  try {
    await session.captureScreenshot("screenshot-viewport-final.png", "viewport");
    await session.captureScreenshot("screenshot-full-final.png", "full");
  } catch {}

  const run = {
    snapshot: session.snapshot(),
    events,
    scenario: options.scenario,
    sessionOutputDir,
  };
  const exportResult = options.exportAssets
    ? await exportSessionAssets({
        sessionIdOrPath: sessionOutputDir,
        outputDir: options.outputDir,
        root,
      })
    : undefined;

  return {
    ok: true,
    kind: "source-run",
    driver,
    profile,
    run,
    export: exportResult,
  };
}
