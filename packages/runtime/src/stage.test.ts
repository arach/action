import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { normalizeHexColor, parseStageWorld } from "./stage.js";

describe("parseStageWorld", () => {
  test("defaults to a normal-level drape and no subjects", () => {
    assert.deepEqual(parseStageWorld({}), {
      mode: "drape",
      color: "0e0d0a",
      level: "normal",
      subjects: [],
    });
  });

  test("accepts a declarative world", () => {
    assert.deepEqual(
      parseStageWorld({
        mode: "drape",
        color: "#1e1e2e",
        subjects: [
          { bundleId: "to.talkie.agent.dev", title: "Settings" },
          { bundleId: "com.googlecode.iterm2" },
        ],
      }),
      {
        mode: "drape",
        color: "1e1e2e",
        level: "normal",
        subjects: [
          { bundleId: "to.talkie.agent.dev", title: "Settings" },
          { bundleId: "com.googlecode.iterm2" },
        ],
      },
    );
  });

  test("space mode keeps the sheet on the current Space", () => {
    assert.equal(parseStageWorld({ mode: "space" }).mode, "space");
  });

  test("rejects a wallpaper-shaped color", () => {
    assert.throws(() => normalizeHexColor("not-a-color"), /Invalid stage color/);
  });
});
