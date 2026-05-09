#!/usr/bin/env bun

import { access } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const distPath = join(rootPath, "dist");

const build = spawnSync("bun", ["scripts/build.mjs"], {
  cwd: rootPath,
  stdio: "inherit",
});

if (build.status !== 0) {
  process.exit(build.status ?? 1);
}

await access(distPath);

spawnSync("open", ["-a", "Google Chrome", "chrome://extensions/"], {
  stdio: "ignore",
});
spawnSync("open", ["-R", distPath], {
  stdio: "ignore",
});

console.log("");
console.log("Action Chrome Companion is built.");
console.log("");
console.log("Chrome requires unpacked extensions to be approved in the UI:");
console.log("1. Enable Developer mode in chrome://extensions.");
console.log("2. Click Load unpacked.");
console.log(`3. Select ${distPath}.`);
console.log("");
console.log("Then run:");
console.log("  bun run bridge");
console.log("  bun run health");
