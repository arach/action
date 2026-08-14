import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AGENT_CURSOR_IDLE_EXPIRY_MS,
  POINTER_FOCUS_COUNTDOWN_SECONDS,
  POINTER_FOCUS_COUNTDOWN_STEP_MS,
  agentCursorExpiration,
  pointFromBounds,
  requiresPointerFocusWarning,
  runPointerFocusCountdown,
} from "./drive-cursor.js";

describe("agent cursor lifecycle", () => {
  test("renews its deadline for the drive idle window", () => {
    const updatedAt = "2026-08-12T12:00:00.000Z";
    assert.equal(
      Date.parse(agentCursorExpiration(updatedAt)) - Date.parse(updatedAt),
      AGENT_CURSOR_IDLE_EXPIRY_MS,
    );
  });

  test("targets the center of resolved bounds", () => {
    assert.deepEqual(
      pointFromBounds({ x: 10, y: 20, width: 80, height: 40 }),
      { x: 50, y: 40 },
    );
  });

  test("warns only for attention-taking execution paths", () => {
    const action = {
      id: "action-1",
      kind: "click" as const,
      description: "Press Save",
    };
    assert.equal(requiresPointerFocusWarning({
      action,
      axTier: "semantic",
      channel: "native",
    }), false);
    assert.equal(requiresPointerFocusWarning({
      action,
      axTier: "attention",
      channel: "hid",
    }), true);
    assert.equal(requiresPointerFocusWarning({
      action: { ...action, target: { point: { x: 10, y: 20 } } },
      axTier: "semantic",
      channel: "native",
    }), true);
    assert.equal(requiresPointerFocusWarning({
      action: { ...action, kind: "focus-window" },
      axTier: "target-focus",
      channel: "native",
    }), true);
  });

  test("keeps the warning cadence explicit and rejects invalid timing", async () => {
    assert.equal(POINTER_FOCUS_COUNTDOWN_SECONDS, 3);
    assert.equal(POINTER_FOCUS_COUNTDOWN_STEP_MS, 800);
    await assert.rejects(
      runPointerFocusCountdown({ leaseId: "test", seconds: 0 }),
      /positive integer/,
    );
    await assert.rejects(
      runPointerFocusCountdown({ leaseId: "test", stepMs: -1 }),
      /non-negative number/,
    );
  });
});
