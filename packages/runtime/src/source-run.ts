import { compileScenario, type ScenarioDocument } from "@action/compiler";
import type {
  CaptureProfile,
  GuidedSessionEvent,
  HudSnapshot,
} from "@action/protocol";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import { exportSessionAssets, type SessionAssetExportResult } from "./asset-export.js";
import { BrowserSourceEngine } from "./browser-source-engine.js";
import { GuidedCaptureSession, MockCaptureEngine } from "./guided.js";
import { MacOSCommandEngine } from "./macos.js";

export type SourceRunDriver = "mock" | "macos" | "browser";

export interface ScenarioSourceRunOptions {
  scenario: ScenarioDocument;
  driver?: SourceRunDriver;
  captureProfile?: CaptureProfile;
  exportAssets?: boolean;
  outputDir?: string;
  root?: string;
  browserUrl?: string;
  browserSession?: string;
}

export interface ScenarioSourceRunResult {
  ok: true;
  kind: "source-run";
  driver: SourceRunDriver;
  profile: CaptureProfile;
  reportPath: string;
  run: {
    snapshot: HudSnapshot;
    events: GuidedSessionEvent[];
    scenario: ScenarioDocument;
    sessionOutputDir: string;
  };
  export?: SessionAssetExportResult;
}

interface SourceRunReport {
  schemaVersion: 1;
  kind: "source-run-report";
  generatedAt: string;
  scenario: {
    id: string;
    title: string;
    goal: string;
  };
  driver: SourceRunDriver;
  profile: CaptureProfile;
  session: {
    id: string;
    state: HudSnapshot["state"];
    phase: HudSnapshot["phase"];
    outputDir: string;
    elapsedMs: number;
    targetApp?: string;
  };
  counts: {
    actions: number;
    events: number;
    artifacts: number;
  };
  artifacts: Array<{
    kind: string;
    path: string;
  }>;
  export?: {
    exportDir: string;
    handoffManifestPath: string;
    primaryVideoPath: string;
  };
}

function now(): string {
  return new Date().toISOString();
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
  const root = options.root ?? process.cwd();
  const profile = options.captureProfile ?? (driver === "mock" ? "draft" : "final");

  if (options.exportAssets && driver === "mock") {
    throw new Error("source run export requires the macos or browser driver because exports verify real media captures");
  }

  const nativeHostPath = resolve(root, "native", "engine", "scripts", "run-app-host.sh");
  const engine = driver === "macos"
    ? new MacOSCommandEngine(nativeHostPath)
    : driver === "browser"
      ? new BrowserSourceEngine({
          url: options.browserUrl ?? options.scenario.run?.browserUrl ?? "http://localhost:3100",
          sessionName: options.browserSession
            ?? options.scenario.run?.browserSession
            ?? `source-${options.scenario.id}-${Date.now()}`,
          cwd: root,
          viewport: options.scenario.stage.viewport.bounds,
          nativeHostPath,
        })
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

  let captureMayBeActive = false;
  try {
    captureMayBeActive = true;
    await session.beginRun(timeline);
    await session.stop();
    captureMayBeActive = false;
  } catch (error) {
    if (captureMayBeActive) {
      const detail = error instanceof Error ? error.message : "Unknown source run failure";
      await session.fail(detail).catch(async () => {
        await session.clearStage().catch(() => undefined);
      });
    }
    throw error;
  }
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
  const reportPath = resolve(sessionOutputDir, "source-run-report.json");
  await writeSourceRunReport(reportPath, buildSourceRunReport({
    scenario: options.scenario,
    driver,
    profile,
    run,
  }));

  const exportResult = options.exportAssets
    ? await exportSessionAssets({
        sessionIdOrPath: sessionOutputDir,
        outputDir: options.outputDir,
        root,
      })
    : undefined;
  if (exportResult) {
    const report = buildSourceRunReport({
      scenario: options.scenario,
      driver,
      profile,
      run,
      exportResult,
    });
    await writeSourceRunReport(reportPath, report);
    await writeSourceRunReport(resolve(exportResult.exportDir, "source-run-report.json"), report);
  }

  return {
    ok: true,
    kind: "source-run",
    driver,
    profile,
    reportPath,
    run,
    export: exportResult,
  };
}

function buildSourceRunReport(input: {
  scenario: ScenarioDocument;
  driver: SourceRunDriver;
  profile: CaptureProfile;
  run: ScenarioSourceRunResult["run"];
  exportResult?: SessionAssetExportResult;
}): SourceRunReport {
  return {
    schemaVersion: 1,
    kind: "source-run-report",
    generatedAt: now(),
    scenario: {
      id: input.scenario.id,
      title: input.scenario.title,
      goal: input.scenario.scene.goal,
    },
    driver: input.driver,
    profile: input.profile,
    session: {
      id: input.run.snapshot.sessionId,
      state: input.run.snapshot.state,
      phase: input.run.snapshot.phase,
      outputDir: input.run.sessionOutputDir,
      elapsedMs: input.run.snapshot.elapsedMs,
      targetApp: input.run.snapshot.targetApp,
    },
    counts: {
      actions: input.scenario.scene.sequence.length,
      events: input.run.events.length,
      artifacts: input.run.snapshot.artifacts.length,
    },
    artifacts: input.run.snapshot.artifacts.map((artifact) => ({
      kind: artifact.kind,
      path: artifact.path,
    })),
    export: input.exportResult
      ? {
          exportDir: input.exportResult.exportDir,
          handoffManifestPath: input.exportResult.handoffManifestPath,
          primaryVideoPath: input.exportResult.primaryVideoPath,
        }
      : undefined,
  };
}

async function writeSourceRunReport(path: string, report: SourceRunReport): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(report, null, 2)}\n`);
}
