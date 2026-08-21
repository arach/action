#!/usr/bin/env bun

import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";

type JsonObject = Record<string, unknown>;

const scriptDir = dirname(fileURLToPath(import.meta.url));
const actionRoot = resolve(process.env.ACTION_ROOT ?? resolve(scriptDir, "../../.."));
const mcpEntry = resolve(actionRoot, "packages/mcp/src/index.ts");
const agentPort = 45_000 + (process.pid % 10_000);

function envRecord(): Record<string, string> {
  return Object.fromEntries(
    Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
}

function structured(result: CallToolResult): JsonObject {
  if (result.isError) {
    const detail = result.content
      .filter((item) => item.type === "text")
      .map((item) => item.text)
      .join("\n");
    throw new Error(detail || "Action MCP tool returned an error");
  }
  if (result.structuredContent && typeof result.structuredContent === "object") {
    return result.structuredContent as JsonObject;
  }
  const text = result.content.find((item) => item.type === "text")?.text;
  assert.ok(text, "Action MCP tool did not return structured or text content");
  return JSON.parse(text) as JsonObject;
}

async function call(client: Client, name: string, args: JsonObject = {}): Promise<JsonObject> {
  const result = await client.callTool({ name, arguments: args });
  return structured(result as unknown as CallToolResult);
}

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [mcpEntry],
  cwd: "/private/tmp",
  env: {
    ...envRecord(),
    ACTION_ROOT: actionRoot,
    ACTION_AGENT_PORT: String(agentPort),
  },
  stderr: "inherit",
});
const client = new Client(
  { name: "action-native-regression", version: "0.0.0" },
  { capabilities: {} },
);

let leaseId: string | undefined;

try {
  await client.connect(transport);

  const listed = await client.listTools();
  const toolNames = new Set(listed.tools.map((tool) => tool.name));
  for (const required of ["action.health", "action.observe.ax", "action.drive.begin", "action.act.execute"]) {
    assert.ok(toolNames.has(required), `Missing MCP tool ${required}`);
  }

  const health = await call(client, "action.health");
  assert.equal(health.ok, true);
  assert.equal(health.nativeAgentPort, agentPort);
  const diagnostics = health.diagnostics as JsonObject;
  assert.equal(diagnostics.accessibility, "granted", "Accessibility must be granted to the signed Action runtime");
  assert.equal(diagnostics.screenRecording, "granted", "Screen Recording must be granted to the signed Action runtime");

  const begun = await call(client, "action.drive.begin", {
    agent: "Action MCP regression",
    task: "Verify native MCP lifecycle",
    mode: "background",
  });
  assert.equal(begun.ok, true);
  leaseId = String(begun.leaseId);

  const observed = await call(client, "action.observe.ax", { leaseId });
  assert.equal(observed.ok, true);
  assert.ok(Number(observed.nodeCount) > 0, "AX observation should return at least one node");

  const accessoryBundleId = process.env.ACTION_MCP_ACCESSORY_BUNDLE_ID ?? "com.apple.systemuiserver";
  const launchedAccessory = await call(client, "action.act.execute", {
    leaseId,
    action: {
      id: "native_mcp_launch_accessory_app",
      kind: "open-app",
      description: "Verify process-based launch success for an LSUIElement-style app",
      input: { bundleId: accessoryBundleId },
    },
  });
  assert.equal(launchedAccessory.ok, true);
  assert.equal((launchedAccessory.result as JsonObject).status, "succeeded");

  const acted = await call(client, "action.act.execute", {
    leaseId,
    action: {
      id: "native_mcp_press_escape",
      kind: "press-key",
      description: "Press Escape without changing document content",
      input: { key: "escape" },
    },
  });
  assert.equal(acted.ok, true);
  assert.equal((acted.result as JsonObject).status, "succeeded");

  // This request uses the same persistent native connection. If the direct-launched agent
  // regresses to NSApplication.shared, it aborts and this assertion fails after press-key.
  const status = await call(client, "action.drive.status", { leaseId });
  assert.equal(status.ok, true);
  assert.equal((status.lease as JsonObject).status, "driving");

  await call(client, "action.drive.release", {
    leaseId,
    outcome: "done",
    summary: "Native MCP health, AX observation, and press-key passed",
  });
  leaseId = undefined;

  process.stdout.write(`${JSON.stringify({
    ok: true,
    actionRoot,
    agentPort,
    diagnostics,
    observedNodes: observed.nodeCount,
    launchedAccessoryBundleId: accessoryBundleId,
    pressKey: (acted.result as JsonObject).status,
    agentAliveAfterPressKey: true,
  }, null, 2)}\n`);
} finally {
  if (leaseId) {
    await call(client, "action.drive.release", {
      leaseId,
      outcome: "cancelled",
      summary: "Native MCP regression interrupted",
    }).catch(() => {});
  }
  await transport.close().catch(() => {});
}
