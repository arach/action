import type {
  ExtractionQuery,
  RuntimeAction,
  SurfaceRef,
  TargetCandidate,
  TargetQuery,
} from "@action/protocol";
import {
  baseObservation,
  candidateFromSurface,
  defaultVerification,
  emptyExtractionResult,
  evidence,
  unsupportedActionResult,
} from "./helpers.js";
import type { SurfaceAdapter } from "./types.js";

const chromeBundleId = "com.google.Chrome";

function surfaceLooksLikeChrome(surface: SurfaceRef): boolean {
  return surface.id.includes("com_google_chrome")
    || surface.label.toLowerCase().includes("chrome");
}

export const chromeAdapter: SurfaceAdapter = {
  id: "chrome",
  label: "Chrome",
  priority: 80,
  capabilities: ["observe", "resolve", "act", "extract", "capture-hints", "verify"],

  canHandle(surface: SurfaceRef) {
    const matched = surface.kind === "window" && surfaceLooksLikeChrome(surface);
    return {
      matched,
      confidence: matched ? 0.72 : 0,
      reason: matched
        ? "Chrome window detected; DOM companion can enrich AX observation when installed."
        : "Surface is not a Chrome window.",
      evidence: { bundleId: matched ? chromeBundleId : undefined },
    };
  },

  async observe(context) {
    return baseObservation(context.surface, context, {
      kind: "browser-page",
      browser: "chrome",
      elements: [],
      metadata: {
        status: "stub",
        next: "Pair with Action Chrome Companion for DOM observe/resolve/act/extract.",
      },
    });
  },

  async resolve(query: TargetQuery, observation): Promise<TargetCandidate[]> {
    return [
      {
        ...candidateFromSurface(observation.surface, query.text ?? query.semanticId ?? "Chrome page target", "dom"),
        confidence: 0.5,
        evidence: [
          evidence("dom", "Chrome DOM resolution stub; waiting for companion bridge.", {
            rect: observation.surface.bounds,
            confidence: 0.5,
          }),
        ],
        fallbackChannels: ["ax", "process", "hid"],
      },
    ];
  },

  async act(action: RuntimeAction) {
    return unsupportedActionResult(
      action.id,
      "dom",
      "Chrome adapter is scaffolded; companion bridge is not wired to runtime actions yet.",
    );
  },

  async extract(query: ExtractionQuery) {
    return emptyExtractionResult(query, {
      status: "stub",
      companion: "@action/chrome-companion",
    });
  },

  async captureHints(target) {
    return target.rect
      ? [
          {
            id: `${target.id}:chrome-crop`,
            label: target.label,
            rect: target.rect,
            reason: "Chrome target candidate frame",
            padding: 32,
            preferredAspectRatio: "16:9",
            evidence: target.evidence,
          },
        ]
      : [];
  },

  async verify() {
    return defaultVerification("Chrome adapter verification is pending companion bridge integration.");
  },
};
