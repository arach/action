import { access, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

import type { DriveLease, Point } from "@action/protocol";

export const AGENT_CURSOR_IDLE_EXPIRY_MS = 90_000;

export interface AgentCursorState {
  x?: number;
  y?: number;
  agent?: string;
  label?: string;
  phase?: "idle" | "click" | "type" | "key" | string;
  typingText?: string;
  keyLabel?: string;
  cueId?: string;
  expiresAt?: string;
  updatedAt?: string;
}

function cursorDirectory(): string {
  return join(homedir(), "Library/Application Support/Action/runtime/drive/cursors");
}

function sanitizeID(raw: string): string {
  return raw.replace(/[^A-Za-z0-9._-]+/g, "_");
}

export function agentCursorStatePath(leaseId: string): string {
  return join(cursorDirectory(), `${sanitizeID(leaseId)}.json`);
}

export function agentCursorStopPath(leaseId: string): string {
  return `${agentCursorStatePath(leaseId)}.stop`;
}

export function agentCursorExpiration(updatedAt: string): string {
  const parsed = Date.parse(updatedAt);
  const base = Number.isFinite(parsed) ? parsed : Date.now();
  return new Date(base + AGENT_CURSOR_IDLE_EXPIRY_MS).toISOString();
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

export async function startAgentCursor(input: {
  nativeHostPath: string;
  lease: DriveLease;
  point?: Point;
  label?: string;
}): Promise<void> {
  const statePath = agentCursorStatePath(input.lease.leaseId);
  const stopPath = agentCursorStopPath(input.lease.leaseId);
  await mkdir(cursorDirectory(), { recursive: true });

  if (await pathExists(statePath)) {
    await writeFile(stopPath, "stop\n");
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 200));
  }
  await rm(stopPath, { force: true });

  const updatedAt = new Date().toISOString();
  const state: AgentCursorState = {
    x: input.point?.x,
    y: input.point?.y,
    agent: input.lease.agent,
    label: input.label ?? input.lease.task,
    phase: "idle",
    expiresAt: agentCursorExpiration(updatedAt),
    updatedAt,
  };
  await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);

  await spawnHostDetached(input.nativeHostPath, [
    "agent-cursor-overlay",
    "--state-file",
    statePath,
    "--stop-file",
    stopPath,
    "--lease-stop-file",
    input.lease.stopFile,
  ]);
}

export async function updateAgentCursor(input: {
  leaseId: string;
  agent?: string;
  point?: Point;
  label?: string;
  phase?: "idle" | "click" | "type" | "key";
  typingText?: string;
  keyLabel?: string;
  cueId?: string;
}): Promise<void> {
  const statePath = agentCursorStatePath(input.leaseId);
  let previous: AgentCursorState = {};
  try {
    previous = JSON.parse(await readFile(statePath, "utf8")) as AgentCursorState;
  } catch {
    return;
  }

  const updatedAt = new Date().toISOString();
  const next: AgentCursorState = {
    ...previous,
    x: input.point?.x ?? previous.x,
    y: input.point?.y ?? previous.y,
    agent: input.agent ?? previous.agent,
    label: input.label ?? previous.label,
    phase: input.phase ?? "idle",
    typingText: input.typingText,
    keyLabel: input.keyLabel,
    cueId: input.cueId ?? previous.cueId,
    expiresAt: agentCursorExpiration(updatedAt),
    updatedAt,
  };
  if (next.phase === "idle") {
    next.typingText = undefined;
    next.keyLabel = undefined;
  }
  await writeFile(statePath, `${JSON.stringify(next, null, 2)}\n`);
}

export async function stopAgentCursor(leaseId: string): Promise<void> {
  await mkdir(cursorDirectory(), { recursive: true });
  await writeFile(agentCursorStopPath(leaseId), "stop\n");
}

export function pointFromBounds(bounds: {
  x: number;
  y: number;
  width: number;
  height: number;
}): Point {
  return {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  };
}

function spawnHostDetached(nativeHostPath: string, args: string[]): Promise<void> {
  return new Promise<void>((resolvePromise, reject) => {
    const child = spawn(nativeHostPath, args, {
      stdio: "ignore",
      detached: true,
    });
    child.once("error", reject);
    child.once("spawn", () => {
      child.unref();
      resolvePromise();
    });
  });
}
