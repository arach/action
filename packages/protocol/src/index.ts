export const sessionStates = [
  "created",
  "preflight",
  "ready",
  "running",
  "paused",
  "completing",
  "completed",
  "failed",
  "cancelled",
] as const;

export type SessionState = (typeof sessionStates)[number];

export const targetResolutionModes = [
  "semantic",
  "accessibility",
  "dom",
  "textual",
  "anchor",
  "coordinate",
] as const;

export type TargetResolutionMode = (typeof targetResolutionModes)[number];

export interface SessionId {
  value: string;
}

export interface Point {
  x: number;
  y: number;
}

export interface Bounds extends Point {
  width: number;
  height: number;
}

export interface SurfaceRef {
  id: string;
  kind: "desktop" | "window" | "browser-tab" | "region";
  label: string;
  bounds?: Bounds;
}

export interface TargetQuery {
  semanticId?: string;
  text?: string;
  role?: string;
  surfaceId?: string;
  anchorId?: string;
  point?: Point;
}

export interface ResolvedTarget {
  id: string;
  mode: TargetResolutionMode;
  confidence: number;
  label: string;
  surfaceId?: string;
  bounds?: Bounds;
  ambiguousWith?: string[];
}

export interface Observation {
  kind:
    | "window"
    | "accessibility"
    | "dom"
    | "cursor"
    | "recording"
    | "audio";
  source: "engine" | "browser" | "runtime";
  at: string;
  surfaceId?: string;
  data: Record<string, unknown>;
}

export type ActionKind =
  | "click"
  | "type"
  | "press-key"
  | "focus-window"
  | "open-app"
  | "drag"
  | "start-recording"
  | "stop-recording"
  | "show-cue"
  | "wait-for-condition";

export interface RuntimeAction {
  id: string;
  kind: ActionKind;
  description: string;
  target?: TargetQuery;
  input?: Record<string, unknown>;
}

export interface Cue {
  id: string;
  kind: "label" | "chapter" | "subtitle" | "callout" | "caption";
  text: string;
  atMs?: number;
  durationMs?: number;
}

export type ArtifactKind =
  | "screenshot"
  | "raw-capture"
  | "trace"
  | "focus-metadata"
  | "subtitle"
  | "render-manifest"
  | "final-video";

export interface RuntimeArtifact {
  kind: ArtifactKind;
  path: string;
  metadata?: Record<string, unknown>;
}

export type PermissionState = "granted" | "denied" | "unknown";

export type CaptureProfile = "draft" | "final";

export interface EngineDiagnostics {
  accessibility: PermissionState;
  screenRecording: PermissionState;
  notes?: string[];
}

export const guidedSessionPhases = [
  "created",
  "staging",
  "countdown",
  "recording",
  "paused",
  "completing",
  "completed",
  "failed",
  "cancelled",
] as const;

export type GuidedSessionPhase = (typeof guidedSessionPhases)[number];

export type BackdropPreset = "neutral" | "spotlight" | "studio" | "gradient" | "matte";

export interface TargetApp {
  name: string;
  bundleId: string;
}

export interface StageViewport {
  id: string;
  bounds: Bounds;
  surfaceId?: string;
  dimming: "none" | "surround";
}

export interface StageInputOverlay {
  kind: "keys" | "typing";
  keys?: string[];
  text?: string;
  style?: "default" | "notes" | "terminal" | "code";
}

export interface StageScene {
  backdrop: BackdropPreset;
  viewport?: StageViewport;
  targetApp?: TargetApp;
}

export interface StagePresentation {
  sessionId: string;
  phase: GuidedSessionPhase;
  backdrop: BackdropPreset;
  viewport?: StageViewport;
  targetApp?: string;
  summary: string;
  detail?: string;
  countdownRemaining?: number;
  elapsedMs?: number;
  isRecording: boolean;
  stepCurrent?: number;
  stepTotal?: number;
  stepLabel?: string;
  inputOverlay?: StageInputOverlay;
  recentLogs?: string[];
}

export type HudControl =
  | "start"
  | "pause"
  | "stop"
  | "replay-last-run"
  | "quit";

export interface HudControlState {
  control: HudControl;
  enabled: boolean;
  label?: string;
}

export interface HudLogEntry {
  id: string;
  at: string;
  level: "info" | "warning" | "error";
  eventType: string;
  message: string;
}

export interface HudSnapshot {
  sessionId: string;
  state: SessionState;
  phase: GuidedSessionPhase;
  targetApp?: string;
  elapsedMs: number;
  isRecording: boolean;
  diagnostics?: EngineDiagnostics;
  controls: HudControlState[];
  logs: HudLogEntry[];
  artifacts: RuntimeArtifact[];
  stage: StageScene;
}

export interface SessionSnapshot {
  id: string;
  state: SessionState;
  createdAt: string;
  updatedAt: string;
  traceCount: number;
  artifactCount: number;
}

export interface TransitionOptions {
  reason?: string;
  at?: string;
}

export interface ActionTrace {
  action: RuntimeAction;
  status: "planned" | "started" | "completed" | "failed";
  at: string;
  detail?: string;
}

export type TraceEvent =
  | {
      type: "session.state_changed";
      at: string;
      from: SessionState;
      to: SessionState;
      reason?: string;
    }
  | {
      type: "observation.recorded";
      at: string;
      observation: Observation;
    }
  | {
      type: "target.resolved";
      at: string;
      query: TargetQuery;
      result: ResolvedTarget;
    }
  | {
      type: "action.recorded";
      at: string;
      entry: ActionTrace;
    }
  | {
      type: "artifact.registered";
      at: string;
      artifact: RuntimeArtifact;
    };

export interface CompiledTimelineStep {
  id: string;
  action: RuntimeAction;
  preconditions: string[];
  cueIds: string[];
  onAmbiguous: "pause" | "fail";
}

export interface CompiledTimeline {
  goal: string;
  cues: Cue[];
  steps: CompiledTimelineStep[];
}

export type GuidedSessionEventType =
  | "phase.changed"
  | "backdrop.selected"
  | "viewport.updated"
  | "app.launched"
  | "countdown.tick"
  | "recording.started"
  | "recording.paused"
  | "recording.resumed"
  | "recording.stopped"
  | "target.resolved"
  | "action.started"
  | "action.completed"
  | "action.failed"
  | "artifact.created"
  | "replay.requested";

export interface GuidedSessionEvent<TPayload extends Record<string, unknown> = Record<string, unknown>> {
  sessionId: string;
  at: string;
  type: GuidedSessionEventType;
  summary: string;
  payload: TPayload;
}

export interface CaptureStartRequest {
  sessionId: string;
  outputPath: string;
  viewport?: StageViewport;
  profile?: CaptureProfile;
}

export interface CaptureEngine {
  diagnostics(): Promise<EngineDiagnostics>;
  requestPermissions(): Promise<EngineDiagnostics>;
  openPermissionSettings(kind: "accessibility" | "screen-recording"): Promise<void>;
  presentStage(presentation: StagePresentation): Promise<void>;
  clearStage(): Promise<void>;
  setBackdrop(backdrop: BackdropPreset): Promise<void>;
  launchApp(app: TargetApp): Promise<SurfaceRef>;
  focusSurface(surfaceId: string): Promise<void>;
  configureViewport(viewport: StageViewport): Promise<StageViewport>;
  startCapture(request: CaptureStartRequest): Promise<void>;
  pauseCapture(): Promise<void>;
  resumeCapture(): Promise<void>;
  stopCapture(): Promise<RuntimeArtifact>;
  captureScreenshot(path: string): Promise<RuntimeArtifact>;
  captureFullScreenshot(path: string): Promise<RuntimeArtifact>;
  consumeStageControls(): Promise<string[]>;
  resolveTarget(query: TargetQuery): Promise<ResolvedTarget>;
  performAction(action: RuntimeAction, target?: ResolvedTarget): Promise<void>;
  replayArtifact(path: string): Promise<void>;
}
