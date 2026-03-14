import { compileScenario, type ScenarioDocument } from "@action/compiler";
import type { GuidedSessionEvent, HudSnapshot } from "@action/protocol";
import { GuidedCaptureSession, MacOSCommandEngine, MockCaptureEngine } from "@action/runtime";
import { resolve } from "node:path";

export function describeCli(): string[] {
  return [
    "action session create",
    "action guided stage",
    "action guided start",
    "action guided pause",
    "action guided stop",
    "action guided replay-last-run",
    "action compose",
    "action export",
  ];
}

export interface GuidedCaptureDemoResult {
  snapshot: HudSnapshot;
  events: GuidedSessionEvent[];
  scenario: ScenarioDocument;
}

export type DemoEngineMode = "mock" | "macos";

export async function runScenarioGuidedCaptureDemo(
  scenario: ScenarioDocument,
  engineMode: DemoEngineMode = "mock",
): Promise<GuidedCaptureDemoResult> {
  const engine = engineMode === "macos"
    ? new MacOSCommandEngine()
    : new MockCaptureEngine();
  const session = new GuidedCaptureSession(engine, {
    sessionId: `session_${scenario.id.replace(/[^a-z0-9]+/gi, "_")}`,
    outputDir: resolve(process.cwd(), "artifacts", "sessions", scenario.id),
    captureProfile: "draft",
    stageHoldMsAfterComplete: 0,
    initialActionDelayMs: 650,
    actionCadenceMs: 900,
  });

  const events: GuidedSessionEvent[] = [];
  session.onEvent((event) => {
    events.push(event);
  });

  await session.stageScene({
    backdrop: scenario.stage.backdrop,
    viewport: scenario.stage.viewport,
    targetApp: scenario.targetApp,
  });

  const { timeline } = compileScenario(scenario);

  await session.beginRun(timeline);
  await session.captureScreenshot("screenshot-viewport-final.png", "viewport");
  await session.captureScreenshot("screenshot-full-final.png", "full");
  const snapshot = await session.stop();

  return {
    snapshot,
    events,
    scenario,
  };
}
