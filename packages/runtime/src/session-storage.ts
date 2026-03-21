import { relative } from "node:path";

import type {
  GuidedSessionPhase,
  HudSnapshot,
  RuntimeArtifact,
  SessionState,
  TraceEvent,
} from "@action/protocol";

export type RuntimeSessionMode = "capture" | "inspection" | "hybrid";

export interface SessionManifestEntry {
  kind: RuntimeArtifact["kind"];
  path: string;
  relativePath: string;
  metadata?: Record<string, unknown>;
}

export interface PersistedRuntimeSession {
  id: string;
  mode: RuntimeSessionMode;
  state: SessionState;
  phase: GuidedSessionPhase;
  createdAt: string;
  updatedAt: string;
  targetApp?: string;
  outputDir: string;
  tracePath: string;
  manifestPath: string;
  artifactCount: number;
  traceCount: number;
  artifacts: SessionManifestEntry[];
  stage: HudSnapshot["stage"];
}

export interface SessionArtifactManifest {
  sessionId: string;
  mode: RuntimeSessionMode;
  generatedAt: string;
  outputDir: string;
  tracePath: string;
  artifacts: SessionManifestEntry[];
}

export function toManifestEntries(outputDir: string, artifacts: RuntimeArtifact[]): SessionManifestEntry[] {
  return artifacts.map((artifact) => ({
    kind: artifact.kind,
    path: artifact.path,
    relativePath: relative(outputDir, artifact.path) || ".",
    metadata: artifact.metadata,
  }));
}

export function buildSessionManifest(input: {
  sessionId: string;
  mode: RuntimeSessionMode;
  generatedAt: string;
  outputDir: string;
  tracePath: string;
  artifacts: RuntimeArtifact[];
}): SessionArtifactManifest {
  return {
    sessionId: input.sessionId,
    mode: input.mode,
    generatedAt: input.generatedAt,
    outputDir: input.outputDir,
    tracePath: input.tracePath,
    artifacts: toManifestEntries(input.outputDir, input.artifacts),
  };
}

export function buildPersistedSession(input: {
  mode: RuntimeSessionMode;
  outputDir: string;
  tracePath: string;
  manifestPath: string;
  snapshot: HudSnapshot;
  createdAt: string;
  updatedAt: string;
  trace: TraceEvent[];
}): PersistedRuntimeSession {
  return {
    id: input.snapshot.sessionId,
    mode: input.mode,
    state: input.snapshot.state,
    phase: input.snapshot.phase,
    createdAt: input.createdAt,
    updatedAt: input.updatedAt,
    targetApp: input.snapshot.targetApp,
    outputDir: input.outputDir,
    tracePath: input.tracePath,
    manifestPath: input.manifestPath,
    artifactCount: input.snapshot.artifacts.length,
    traceCount: input.trace.length,
    artifacts: toManifestEntries(input.outputDir, input.snapshot.artifacts),
    stage: input.snapshot.stage,
  };
}
