import type {
  AdapterActionChannel,
  Bounds,
  MarkupObservation,
  MarkupObservationLine,
  MarkupObservationSource,
  MarkupTargetCandidate,
  MarkupTargetRef,
  Point,
  SemanticElement,
  SurfaceObservation,
  TargetEvidence,
  TargetResolutionMode,
} from "@action/protocol";

export interface BuildMarkupObservationOptions {
  now?: string;
  maxLines?: number;
  maxCandidates?: number;
  minCandidateConfidence?: number;
}

type CandidateDraft = Omit<MarkupTargetCandidate, "id">;

const DEFAULT_MAX_LINES = 80;
const DEFAULT_MAX_CANDIDATES = 40;
const DEFAULT_MIN_CONFIDENCE = 0.35;

export function buildMarkupObservation(
  observation: SurfaceObservation,
  options: BuildMarkupObservationOptions = {},
): MarkupObservation {
  const maxLines = options.maxLines ?? DEFAULT_MAX_LINES;
  const maxCandidates = options.maxCandidates ?? DEFAULT_MAX_CANDIDATES;
  const minConfidence = options.minCandidateConfidence ?? DEFAULT_MIN_CONFIDENCE;
  const candidates = buildMarkupTargetCandidates(observation, { ...options, minCandidateConfidence: minConfidence });
  const lines = buildMarkupLines(observation, candidates, maxLines);
  const visionConfidence = numericMetadata(observation.vision?.metadata, "confidence");

  return {
    kind: "markup-observation",
    version: 1,
    at: options.now ?? newestTimestamp(observation),
    surface: observation.surface,
    native: compactObject(observation.native),
    freshness: observation.freshness,
    screenshot: observation.vision?.imagePath || observation.freshness.screenshotCapturedAt
      ? {
          imagePath: observation.vision?.imagePath,
          capturedAt: observation.freshness.screenshotCapturedAt,
        }
      : undefined,
    vision: observation.vision
      ? {
          provider: observation.vision.provider,
          summary: observation.vision.summary,
          confidence: visionConfidence,
          findings: observation.vision.findings,
          metadata: observation.vision.metadata,
        }
      : undefined,
    lines,
    candidates: candidates.slice(0, maxCandidates),
  };
}

export function buildMarkupTargetCandidates(
  observation: SurfaceObservation,
  options: BuildMarkupObservationOptions = {},
): MarkupTargetCandidate[] {
  const minConfidence = options.minCandidateConfidence ?? DEFAULT_MIN_CONFIDENCE;
  const drafts: CandidateDraft[] = [
    ...semanticCandidates(observation),
    ...axCandidates(observation),
    ...nativeCandidates(observation),
  ];

  const seen = new Set<string>();
  const candidates: CandidateDraft[] = [];

  for (const draft of drafts) {
    if (draft.confidence < minConfidence) {
      continue;
    }

    const identity = candidateIdentity(draft);
    if (seen.has(identity)) {
      continue;
    }

    seen.add(identity);
    candidates.push(draft);
  }

  return candidates
    .sort((left, right) => right.confidence - left.confidence)
    .slice(0, options.maxCandidates ?? DEFAULT_MAX_CANDIDATES)
    .map((candidate, index) => ({
      id: `mo:${index + 1}`,
      ...candidate,
    }));
}

function buildMarkupLines(
  observation: SurfaceObservation,
  candidates: MarkupTargetCandidate[],
  maxLines: number,
): MarkupObservationLine[] {
  const lines: MarkupObservationLine[] = [
    line("surface", "surface", surfaceText(observation), {
      ref: observation.surface.id,
      bounds: observation.surface.bounds,
    }),
  ];

  if (hasNativeState(observation)) {
    lines.push(line("window", "window", nativeText(observation), {
      ref: nativeRef(observation),
      bounds: observation.native.bounds,
    }));
  }

  if (observation.vision?.summary) {
    lines.push(line("vision", "vision", observation.vision.summary, {
      ref: observation.vision.imagePath,
      confidence: numericMetadata(observation.vision.metadata, "confidence"),
    }));
  }

  for (const candidate of candidates) {
    lines.push(line(candidate.ref.value, candidate.evidence[0]?.source ?? "recipe", candidateLineText(candidate), {
      ref: candidate.ref.value,
      role: candidate.role,
      bounds: candidate.bounds,
      confidence: candidate.confidence,
      metadata: candidate.ref.coordinateFallback
        ? { coordinateFallback: true, point: candidate.ref.point }
        : undefined,
    }));
  }

  return lines.slice(0, maxLines).map((entry, index) => ({
    ...entry,
    id: `line:${index + 1}`,
  }));
}

function semanticCandidates(observation: SurfaceObservation): CandidateDraft[] {
  return semanticElements(observation.semantic)
    .map((element, index): CandidateDraft => {
      const label = element.label ?? element.text ?? element.id;
      const ref = semanticRef(observation.surface.id, element, index);
      const confidence = element.rect ? 0.86 : 0.72;

      return {
        ref,
        label,
        role: element.role,
        bounds: element.rect,
        confidence,
        preferredActionChannel: "dom",
        fallbackChannels: ref.coordinateFallback ? ["hid"] : ["ax", "hid"],
        evidence: [
          evidence("dom", `Semantic element ${element.role ?? "element"} ${label}`, {
            nodeId: element.id,
            rect: element.rect,
            confidence,
            metadata: compactObject({
              selector: element.selector,
              attributes: element.attributes,
            }),
          }),
        ],
      };
    });
}

function axCandidates(observation: SurfaceObservation): CandidateDraft[] {
  return observation.ax.nodes
    .filter((node) => node.enabled !== false)
    .filter((node) => Boolean(node.title ?? node.detail ?? node.value ?? node.identifier ?? node.frame))
    .map((node, index): CandidateDraft => {
      const label = node.title ?? node.detail ?? node.value ?? node.identifier ?? node.role;
      const ref = axRef(observation.surface.id, node.identifier, node.frame, index);
      const confidence = node.identifier ? 0.78 : node.frame ? 0.64 : 0.48;

      return {
        ref,
        label,
        role: node.role,
        bounds: node.frame,
        confidence,
        preferredActionChannel: "ax",
        fallbackChannels: ref.coordinateFallback ? ["hid"] : ["native", "hid"],
        evidence: [
          evidence("ax", `AX node ${node.role} ${label}`, {
            nodeId: node.identifier,
            rect: node.frame,
            confidence,
            metadata: compactObject({
              depth: node.depth,
              actions: node.actions,
              focused: node.focused,
            }),
          }),
        ],
      };
    });
}

function nativeCandidates(observation: SurfaceObservation): CandidateDraft[] {
  if (!observation.surface.bounds) {
    return [];
  }

  const label = observation.native.windowTitle
    ?? observation.surface.label
    ?? observation.native.appName
    ?? "active surface";
  const ref = nativeWindowRef(observation);

  return [
    {
      ref,
      label,
      role: "window",
      bounds: observation.surface.bounds,
      confidence: 0.4,
      preferredActionChannel: "native",
      fallbackChannels: ["hid"],
      evidence: [
        evidence("native", `Window surface ${label}`, {
          rect: observation.surface.bounds,
          confidence: 0.4,
          metadata: compactObject({
            bundleId: observation.native.bundleId,
            processId: observation.native.processId,
          }),
        }),
      ],
    },
  ];
}

function semanticElements(semantic: SurfaceObservation["semantic"]): SemanticElement[] {
  if (!semantic || typeof semantic !== "object") {
    return [];
  }

  const record = semantic as Record<string, unknown>;
  const arrays = [
    record.elements,
    record.sessions,
    record.panes,
    record.panels,
  ];

  return arrays.flatMap((value) => Array.isArray(value) ? value.filter(isSemanticElement) : []);
}

function semanticRef(surfaceId: string, element: SemanticElement, index: number): MarkupTargetRef {
  const stableValue = element.id || element.selector;

  if (stableValue) {
    return {
      mode: "dom",
      value: `${surfaceId}:dom:${stableValue}`,
      surfaceId,
      bounds: element.rect,
      stable: true,
      coordinateFallback: false,
    };
  }

  return coordinateRef(surfaceId, "dom", element.rect, index);
}

function axRef(surfaceId: string, identifier: string | undefined, frame: Bounds | undefined, index: number): MarkupTargetRef {
  if (identifier) {
    return {
      mode: "accessibility",
      value: `${surfaceId}:ax:${identifier}`,
      surfaceId,
      bounds: frame,
      stable: true,
      coordinateFallback: false,
    };
  }

  return coordinateRef(surfaceId, "accessibility", frame, index);
}

function nativeWindowRef(observation: SurfaceObservation): MarkupTargetRef {
  const bundleId = observation.native.bundleId ?? "unknown";
  const processId = observation.native.processId ? `:${observation.native.processId}` : "";

  return {
    mode: "anchor",
    value: `${observation.surface.id}:window:${bundleId}${processId}`,
    surfaceId: observation.surface.id,
    bounds: observation.surface.bounds,
    stable: Boolean(observation.native.bundleId || observation.native.processId),
    coordinateFallback: false,
  };
}

function coordinateRef(
  surfaceId: string,
  sourceMode: Extract<TargetResolutionMode, "accessibility" | "dom">,
  bounds: Bounds | undefined,
  index: number,
): MarkupTargetRef {
  const point = bounds ? center(bounds) : undefined;

  return {
    mode: "coordinate",
    value: `${surfaceId}:${sourceMode}:coordinate-fallback:${index}`,
    surfaceId,
    bounds,
    point,
    stable: false,
    coordinateFallback: true,
  };
}

function line(
  idSeed: string,
  source: MarkupObservationSource,
  text: string,
  extra: Omit<MarkupObservationLine, "id" | "source" | "text"> = {},
): MarkupObservationLine {
  return {
    id: idSeed,
    source,
    text,
    ...extra,
  };
}

function candidateLineText(candidate: MarkupTargetCandidate): string {
  const role = candidate.role ? `${candidate.role} ` : "";
  const fallback = candidate.ref.coordinateFallback ? " coordinate-fallback" : "";

  return `${role}${candidate.label} [${candidate.ref.mode}:${candidate.ref.value}] confidence=${candidate.confidence.toFixed(2)}${fallback}`;
}

function surfaceText(observation: SurfaceObservation): string {
  const bounds = observation.surface.bounds ? ` ${formatBounds(observation.surface.bounds)}` : "";
  return `${observation.surface.kind} ${observation.surface.label}${bounds}`;
}

function nativeText(observation: SurfaceObservation): string {
  const app = observation.native.appName ?? observation.native.bundleId ?? "unknown app";
  const title = observation.native.windowTitle ? ` "${observation.native.windowTitle}"` : "";
  const frontmost = observation.native.isFrontmost ? " frontmost" : "";
  const bounds = observation.native.bounds ? ` ${formatBounds(observation.native.bounds)}` : "";

  return `${app}${title}${frontmost}${bounds}`;
}

function nativeRef(observation: SurfaceObservation): string {
  return observation.native.bundleId
    ?? observation.native.appName
    ?? observation.surface.id;
}

function evidence(
  source: TargetEvidence["source"],
  summary: string,
  extra: Omit<TargetEvidence, "source" | "summary"> = {},
): TargetEvidence {
  return {
    source,
    summary,
    ...extra,
  };
}

function isSemanticElement(value: unknown): value is SemanticElement {
  if (!value || typeof value !== "object") {
    return false;
  }

  const record = value as Record<string, unknown>;
  return typeof record.id === "string";
}

function candidateIdentity(candidate: CandidateDraft): string {
  if (candidate.ref.stable) {
    return candidate.ref.value;
  }

  const bounds = candidate.bounds ? formatBounds(candidate.bounds) : "no-bounds";
  return `${candidate.label}:${candidate.role ?? "unknown"}:${bounds}`;
}

function newestTimestamp(observation: SurfaceObservation): string {
  return observation.freshness.screenshotCapturedAt
    ?? observation.freshness.semanticCapturedAt
    ?? observation.freshness.axCapturedAt;
}

function hasNativeState(observation: SurfaceObservation): boolean {
  return Object.values(observation.native).some((value) => value !== undefined);
}

function compactObject<T extends object>(value: T | undefined): T | undefined {
  if (!value) {
    return undefined;
  }

  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as T;
}

function numericMetadata(metadata: Record<string, unknown> | undefined, key: string): number | undefined {
  const value = metadata?.[key];
  return typeof value === "number" ? value : undefined;
}

function center(bounds: Bounds): Point {
  return {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  };
}

function formatBounds(bounds: Bounds): string {
  return `${Math.round(bounds.x)},${Math.round(bounds.y)} ${Math.round(bounds.width)}x${Math.round(bounds.height)}`;
}
