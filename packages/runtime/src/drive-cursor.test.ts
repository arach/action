import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AGENT_CURSOR_IDLE_EXPIRY_MS,
  agentCursorExpiration,
  pointFromBounds,
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
});
