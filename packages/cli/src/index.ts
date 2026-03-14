import { compileScenario, type ScenarioDocument } from "@action/compiler";
import type { GuidedSessionEvent, HudSnapshot } from "@action/protocol";
import { GuidedCaptureSession, MacOSCommandEngine, MockCaptureEngine } from "@action/runtime";

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
    outputDir: `artifacts/sessions/${scenario.id}`,
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
  await session.captureScreenshot();
  const snapshot = await session.stop();

  return {
    snapshot,
    events,
    scenario,
  };
}
