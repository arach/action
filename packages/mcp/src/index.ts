#!/usr/bin/env bun

import { execFile } from "node:child_process";
import { access, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";
import type {
  Bounds,
  ResolvedTarget,
  RuntimeAction,
  SessionMode,
  TargetQuery,
} from "@action/protocol";
import { inspectCurrentSurface, MacOSCommandEngine } from "@action/runtime";

export const toolFamilies = [
  "session",
  "observe",
  "resolve",
  "act",
  "record",
  "artifacts",
  "compose",
  "export",
] as const;

type JsonObject = Record<string, unknown>;
type ToolHandler = (args: JsonObject) => Promise<JsonObject>;

interface JsonSchemaObject {
  [key: string]: unknown;
  type: "object";
  properties?: Record<string, object>;
  required?: string[];
  additionalProperties?: boolean;
}

interface RecordingEntry {
  recordingId: string;
  sessionId?: string;
  scope: "current-surface" | "app-window" | "region";
  outputPath: string;
  stopFile: string;
  finishedFile: string;
  debugLog?: string;
  startedAt: string;
  nativeStatus?: string;
  nativeDetail?: string;
  bundleId?: string;
  bounds?: Bounds;
}

const execFileAsync = promisify(execFile);
const sourceDir = dirname(fileURLToPath(import.meta.url));
const defaultActionRoot = resolve(sourceDir, "../../..");
const actionRoot = resolve(process.env.ACTION_ROOT ?? defaultActionRoot);
const nativeHostPath = resolve(
  process.env.ACTION_NATIVE_HOST ?? resolve(actionRoot, "native/engine/scripts/run-app-host.sh"),
);
const activeRecordings = new Map<string, RecordingEntry>();

function now(): string {
  return new Date().toISOString();
}

function timestampId(): string {
  return now().replace(/[-:.]/g, "").replace("T", "_").replace("Z", "");
}

function objectSchema(
  properties: Record<string, object> = {},
  required: string[] = [],
): JsonSchemaObject {
  return {
    type: "object",
    properties,
    required,
    additionalProperties: true,
  };
}

function tool(
  name: string,
  title: string,
  description: string,
  inputSchema: JsonSchemaObject = objectSchema(),
  annotations: Tool["annotations"] = {},
): Tool {
  return {
    name,
    title,
    description,
    inputSchema,
    annotations,
  };
}

function textProperty(description: string): object {
  return { type: "string", description };
}

function booleanProperty(description: string): object {
  return { type: "boolean", description };
}

function numberProperty(description: string): object {
  return { type: "number", description };
}

function objectProperty(description: string): object {
  return { type: "object", description, additionalProperties: true };
}

function enumProperty(values: string[], description: string): object {
  return { type: "string", enum: values, description };
}

function asObject(value: unknown, label: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }

  return value as JsonObject;
}

function optionalObject(value: unknown, label: string): JsonObject | undefined {
  if (value === undefined) {
    return undefined;
  }

  return asObject(value, label);
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function optionalBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function optionalNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return undefined;
}

function parseSessionMode(value: unknown): SessionMode {
  if (value === "inspection" || value === "hybrid" || value === "capture") {
    return value;
  }

  return "inspection";
}

function parseBounds(value: unknown, label = "bounds"): Bounds {
  const object = asObject(value, label);
  const x = optionalNumber(object.x);
  const y = optionalNumber(object.y);
  const width = optionalNumber(object.width);
  const height = optionalNumber(object.height);

  if (x === undefined || y === undefined || width === undefined || height === undefined) {
    throw new Error(`${label} requires numeric x, y, width, and height`);
  }

  return { x, y, width, height };
}

function parseTargetQuery(value: unknown): TargetQuery {
  return asObject(value, "query") as TargetQuery;
}

function parseResolvedTarget(value: unknown): ResolvedTarget {
  return asObject(value, "target") as unknown as ResolvedTarget;
}

function parseRuntimeAction(value: unknown): RuntimeAction {
  const action = asObject(value, "action") as Partial<RuntimeAction>;
  const kind = optionalString(action.kind);

  if (!kind) {
    throw new Error("action.kind is required");
  }

  return {
    id: optionalString(action.id) ?? `action_${timestampId()}`,
    kind: kind as RuntimeAction["kind"],
    description: optionalString(action.description) ?? kind,
    target: action.target,
    input: action.input,
  };
}

function sessionOutputDir(sessionId: string): string {
  return resolve(actionRoot, "artifacts", "sessions", sessionId);
}

function defaultSessionId(mode: SessionMode): string {
  return `${mode}_${timestampId()}`;
}

function defaultRecordingId(): string {
  return `recording_${timestampId()}`;
}

function mcpResult(data: JsonObject): CallToolResult {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(data, null, 2),
      },
    ],
    structuredContent: data,
  };
}

function mcpError(message: string, metadata: JsonObject = {}): CallToolResult {
  return {
    isError: true,
    content: [
      {
        type: "text",
        text: JSON.stringify({ ok: false, error: message, ...metadata }, null, 2),
      },
    ],
    structuredContent: {
      ok: false,
      error: message,
      ...metadata,
    },
  };
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function fileSize(path: string): Promise<number | undefined> {
  try {
    return (await stat(path)).size;
  } catch {
    return undefined;
  }
}

async function readTextIfExists(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return undefined;
  }
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

async function runHost(command: string, ...args: string[]): Promise<JsonObject> {
  const { stdout } = await execFileAsync(nativeHostPath, [command, ...args], {
    cwd: actionRoot,
  });
  const text = stdout.trim();
  if (!text) {
    return {};
  }

  return JSON.parse(text) as JsonObject;
}

function newEngine(): MacOSCommandEngine {
  return new MacOSCommandEngine(nativeHostPath);
}

function recordingMetadataPath(entry: RecordingEntry): string | undefined {
  if (!entry.sessionId) {
    return undefined;
  }

  return resolve(sessionOutputDir(entry.sessionId), `${entry.recordingId}.recording.json`);
}

async function persistRecording(entry: RecordingEntry): Promise<void> {
  const metadataPath = recordingMetadataPath(entry);
  if (metadataPath) {
    await writeJson(metadataPath, entry);
  }
}

async function loadRecordingFromDisk(args: JsonObject): Promise<RecordingEntry | undefined> {
  const recordingId = optionalString(args.recordingId);
  const sessionId = optionalString(args.sessionId);
  if (!recordingId || !sessionId) {
    return undefined;
  }

  const metadataPath = resolve(sessionOutputDir(sessionId), `${recordingId}.recording.json`);
  const raw = await readTextIfExists(metadataPath);
  if (!raw) {
    return undefined;
  }

  return JSON.parse(raw) as RecordingEntry;
}

async function resolveRecording(args: JsonObject): Promise<RecordingEntry> {
  const recordingId = optionalString(args.recordingId);
  if (recordingId && activeRecordings.has(recordingId)) {
    return activeRecordings.get(recordingId)!;
  }

  const diskEntry = await loadRecordingFromDisk(args);
  if (diskEntry) {
    activeRecordings.set(diskEntry.recordingId, diskEntry);
    return diskEntry;
  }

  const outputPath = optionalString(args.outputPath);
  if (outputPath) {
    const resolvedOutputPath = resolve(actionRoot, outputPath);
    return {
      recordingId: recordingId ?? "recording_from_output_path",
      sessionId: optionalString(args.sessionId),
      scope: "region",
      outputPath: resolvedOutputPath,
      stopFile: optionalString(args.stopFile) ?? `${resolvedOutputPath}.stop`,
      finishedFile: optionalString(args.finishedFile) ?? `${resolvedOutputPath}.finished`,
      startedAt: now(),
    };
  }

  throw new Error("recordingId with sessionId, an active recordingId, or outputPath is required");
}

async function statusForRecording(entry: RecordingEntry): Promise<JsonObject> {
  const finishedText = await readTextIfExists(entry.finishedFile);
  const outputSize = await fileSize(entry.outputPath);
  const stopRequested = await pathExists(entry.stopFile);
  let state: "starting" | "recording" | "stopping" | "completed" | "failed" = "starting";
  let finishedStatus: string | undefined;

  if (finishedText !== undefined) {
    finishedStatus = finishedText.trim();
    state = finishedStatus.startsWith("error:") ? "failed" : "completed";
  } else if (stopRequested) {
    state = "stopping";
  } else if (outputSize !== undefined) {
    state = "recording";
  }

  return {
    ok: true,
    recordingId: entry.recordingId,
    sessionId: entry.sessionId,
    scope: entry.scope,
    state,
    outputPath: entry.outputPath,
    outputSize,
    stopFile: entry.stopFile,
    finishedFile: entry.finishedFile,
    finishedStatus,
    debugLog: entry.debugLog,
    startedAt: entry.startedAt,
    nativeStatus: entry.nativeStatus,
    nativeDetail: entry.nativeDetail,
  };
}

async function waitForRecordingFinished(
  entry: RecordingEntry,
  timeoutMs: number,
): Promise<JsonObject> {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const status = await statusForRecording(entry);
    if (status.state === "completed" || status.state === "failed") {
      return status;
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  }

  return statusForRecording(entry);
}

async function listFiles(root: string): Promise<JsonObject[]> {
  const entries: JsonObject[] = [];

  async function visit(dir: string): Promise<void> {
    const dirEntries = await readdir(dir, { withFileTypes: true });
    for (const entry of dirEntries) {
      const path = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        await visit(path);
        continue;
      }

      const stats = await stat(path);
      entries.push({
        path,
        relativePath: relative(root, path),
        bytes: stats.size,
        updatedAt: stats.mtime.toISOString(),
      });
    }
  }

  if (await pathExists(root)) {
    await visit(root);
  }

  return entries;
}

const tools: Tool[] = [
  tool(
    "action.health",
    "Action Health",
    "Check native Action permissions and host availability.",
    objectSchema(),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.session.create",
    "Create Session",
    "Create a durable Action session directory for harness-driven work.",
    objectSchema({
      mode: enumProperty(["capture", "inspection", "hybrid"], "Session mode. Defaults to inspection."),
      sessionId: textProperty("Optional stable session id."),
      outputDir: textProperty("Optional absolute or Action-root-relative output directory."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.snapshot",
    "Observe Snapshot",
    "Capture the current focused surface screenshot and AX snapshot as session artifacts.",
    objectSchema({
      sessionId: textProperty("Optional session id. A new inspection session id is generated when omitted."),
      outputDir: textProperty("Optional absolute or Action-root-relative output directory."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.ax",
    "Observe Accessibility",
    "Capture an accessibility snapshot for the current focused surface.",
    objectSchema({
      sessionId: textProperty("Optional session id used to choose the artifact directory."),
      outputPath: textProperty("Optional absolute or Action-root-relative JSON output path."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.resolve.target",
    "Resolve Target",
    "Resolve a target query through Action's runtime target interface.",
    objectSchema({
      query: objectProperty("TargetQuery object with semanticId, text, role, surfaceId, anchorId, or point."),
    }, ["query"]),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.act.execute",
    "Execute Action",
    "Execute a deterministic runtime action. Prefer resolved targets over raw coordinates.",
    objectSchema({
      action: objectProperty("RuntimeAction object."),
      target: objectProperty("Optional ResolvedTarget. If omitted, action.target is resolved first when present."),
    }, ["action"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.record.start",
    "Start Recording",
    "Start an asynchronous native recording. Completion is represented by the finished file and status tool.",
    objectSchema({
      scope: enumProperty(["current-surface", "app-window", "region"], "Recording target. Defaults from bundleId or bounds, otherwise current-surface."),
      sessionId: textProperty("Optional session id used for default artifact paths."),
      recordingId: textProperty("Optional stable recording id."),
      outputPath: textProperty("Optional absolute or Action-root-relative .mov path."),
      bundleId: textProperty("Bundle id for app-window recording."),
      bounds: objectProperty("Bounds for region recording: x, y, width, height."),
      profile: enumProperty(["draft", "final"], "Region recording quality profile. Defaults to draft."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.record.status",
    "Recording Status",
    "Read recording status from an active recording entry, output path, or finished marker.",
    objectSchema({
      recordingId: textProperty("Recording id returned by action.record.start."),
      sessionId: textProperty("Session id used to reload recording metadata if needed."),
      outputPath: textProperty("Optional .mov path for marker-derived status."),
      stopFile: textProperty("Optional stop marker path when using outputPath."),
      finishedFile: textProperty("Optional finished marker path when using outputPath."),
    }),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.record.stop",
    "Stop Recording",
    "Request a clean recording stop by writing the stop marker and optionally waiting for completion.",
    objectSchema({
      recordingId: textProperty("Recording id returned by action.record.start."),
      sessionId: textProperty("Session id used to reload recording metadata if needed."),
      outputPath: textProperty("Optional .mov path for marker-derived stop."),
      stopFile: textProperty("Optional stop marker path when using outputPath."),
      finishedFile: textProperty("Optional finished marker path when using outputPath."),
      wait: booleanProperty("Whether to wait for the finished marker. Defaults to true."),
      timeoutMs: numberProperty("Maximum wait for the finished marker. Defaults to 30000."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.artifacts.list",
    "List Artifacts",
    "List artifacts for an Action session directory.",
    objectSchema({
      sessionId: textProperty("Session id under artifacts/sessions."),
      outputDir: textProperty("Optional absolute or Action-root-relative artifact directory."),
    }),
    { readOnlyHint: true, idempotentHint: true },
  ),
];

const handlers: Record<string, ToolHandler> = {
  async "action.health"() {
    const engine = newEngine();
    const diagnostics = await engine.diagnostics();

    return {
      ok: true,
      actionRoot,
      nativeHostPath,
      diagnostics,
      toolFamilies,
    };
  },

  async "action.session.create"(args) {
    const mode = parseSessionMode(args.mode);
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId(mode);
    const outputDir = resolve(actionRoot, optionalString(args.outputDir) ?? sessionOutputDir(sessionId));
    const createdAt = now();
    const session = {
      id: sessionId,
      mode,
      state: "created",
      phase: "created",
      createdAt,
      updatedAt: createdAt,
      outputDir,
      tracePath: resolve(outputDir, "trace.json"),
      manifestPath: resolve(outputDir, "manifest.json"),
      artifactCount: 0,
      traceCount: 0,
      artifacts: [],
    };
    const manifest = {
      sessionId,
      mode,
      generatedAt: createdAt,
      outputDir,
      tracePath: session.tracePath,
      artifacts: [],
    };

    await mkdir(outputDir, { recursive: true });
    await writeJson(session.tracePath, []);
    await writeJson(session.manifestPath, manifest);
    await writeJson(resolve(outputDir, "session.json"), session);

    return {
      ok: true,
      session,
      manifest,
    };
  },

  async "action.observe.snapshot"(args) {
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId("inspection");
    const outputDir = resolve(actionRoot, optionalString(args.outputDir) ?? sessionOutputDir(sessionId));
    const result = await inspectCurrentSurface({
      engine: newEngine(),
      sessionId,
      outputDir,
    });

    return {
      ok: true,
      currentSurface: result.currentSurface,
      session: result.session,
      manifest: result.manifest,
    };
  },

  async "action.observe.ax"(args) {
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId("inspection");
    const outputPath = resolve(
      actionRoot,
      optionalString(args.outputPath)
        ?? resolve(sessionOutputDir(sessionId), `ax-snapshot-${timestampId()}.json`),
    );
    const engine = newEngine();
    const currentSurface = await engine.currentSurface();
    const result = await engine.captureSurfaceAccessibilitySnapshot(currentSurface, outputPath);

    return {
      ok: true,
      sessionId,
      currentSurface,
      artifact: result.artifact,
      nodeCount: result.nodeCount,
    };
  },

  async "action.resolve.target"(args) {
    const query = parseTargetQuery(args.query);
    const result = await newEngine().resolveTarget(query);

    return {
      ok: true,
      query,
      result,
    };
  },

  async "action.act.execute"(args) {
    const action = parseRuntimeAction(args.action);
    const engine = newEngine();
    const target = optionalObject(args.target, "target")
      ? parseResolvedTarget(args.target)
      : action.target
        ? await engine.resolveTarget(action.target)
        : undefined;

    await engine.performAction(action, target);

    return {
      ok: true,
      result: {
        id: action.id,
        at: now(),
        status: "succeeded",
        channel: target?.mode === "coordinate" ? "hid" : "native",
        detail: action.description,
      },
      action,
      target,
    };
  },

  async "action.record.start"(args) {
    const sessionId = optionalString(args.sessionId);
    const recordingId = optionalString(args.recordingId) ?? defaultRecordingId();
    const scope = (() => {
      const explicit = optionalString(args.scope);
      if (explicit === "current-surface" || explicit === "app-window" || explicit === "region") {
        return explicit;
      }
      if (args.bounds !== undefined) {
        return "region";
      }
      if (optionalString(args.bundleId)) {
        return "app-window";
      }
      return "current-surface";
    })();
    const outputPath = resolve(
      actionRoot,
      optionalString(args.outputPath)
        ?? resolve(sessionOutputDir(sessionId ?? "mcp"), `${recordingId}.mov`),
    );
    const stopFile = `${outputPath}.stop`;
    const finishedFile = `${outputPath}.finished`;
    const debugLog = `${outputPath}.log`;

    await mkdir(dirname(outputPath), { recursive: true });
    await rm(outputPath, { force: true });
    await rm(stopFile, { force: true });
    await rm(finishedFile, { force: true });
    await rm(debugLog, { force: true });

    let nativeResponse: JsonObject;
    let bundleId = optionalString(args.bundleId);
    let bounds: Bounds | undefined;

    if (scope === "current-surface") {
      const currentSurface = await newEngine().currentSurface();
      bundleId = currentSurface.bundleId;
      nativeResponse = await runHost(
        "record-app-window",
        "--bundle-id",
        currentSurface.bundleId,
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
        "--debug-log",
        debugLog,
      );
    } else if (scope === "app-window") {
      if (!bundleId) {
        throw new Error("bundleId is required for app-window recording");
      }
      nativeResponse = await runHost(
        "record-app-window",
        "--bundle-id",
        bundleId,
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
        "--debug-log",
        debugLog,
      );
    } else {
      bounds = parseBounds(args.bounds);
      const profile = optionalString(args.profile) === "final" ? "final" : "draft";
      nativeResponse = await runHost(
        "record-region",
        "--x",
        String(bounds.x),
        "--y",
        String(bounds.y),
        "--width",
        String(bounds.width),
        "--height",
        String(bounds.height),
        "--fps",
        profile === "final" ? "30" : "15",
        "--scale",
        profile === "final" ? "1" : "0.75",
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
        "--debug-log",
        debugLog,
      );
    }

    const entry: RecordingEntry = {
      recordingId,
      sessionId,
      scope,
      outputPath,
      stopFile,
      finishedFile,
      debugLog,
      startedAt: now(),
      nativeStatus: optionalString(nativeResponse.status),
      nativeDetail: optionalString(nativeResponse.detail),
      bundleId,
      bounds,
    };
    activeRecordings.set(recordingId, entry);
    await persistRecording(entry);

    return {
      ok: true,
      status: "recording-started",
      recording: entry,
      nativeResponse,
      completion: {
        note: "Recording start is an acknowledgement only. Use action.record.status or the finishedFile marker for completion.",
        finishedFile,
      },
    };
  },

  async "action.record.status"(args) {
    return statusForRecording(await resolveRecording(args));
  },

  async "action.record.stop"(args) {
    const entry = await resolveRecording(args);
    const wait = optionalBoolean(args.wait) ?? true;
    const timeoutMs = optionalNumber(args.timeoutMs) ?? 30_000;

    await mkdir(dirname(entry.stopFile), { recursive: true });
    await writeFile(entry.stopFile, "stop\n");

    const status = wait
      ? await waitForRecordingFinished(entry, timeoutMs)
      : await statusForRecording(entry);

    return {
      ok: true,
      stopRequested: true,
      ...status,
    };
  },

  async "action.artifacts.list"(args) {
    const outputDir = resolve(
      actionRoot,
      optionalString(args.outputDir)
        ?? sessionOutputDir(optionalString(args.sessionId) ?? "mcp"),
    );
    const manifestPath = resolve(outputDir, "manifest.json");
    const sessionPath = resolve(outputDir, "session.json");
    const manifestRaw = await readTextIfExists(manifestPath);
    const sessionRaw = await readTextIfExists(sessionPath);

    return {
      ok: true,
      outputDir,
      manifest: manifestRaw ? JSON.parse(manifestRaw) : undefined,
      session: sessionRaw ? JSON.parse(sessionRaw) : undefined,
      files: await listFiles(outputDir),
    };
  },
};

function createServer(): Server {
  const server = new Server(
    {
      name: "@action/mcp",
      version: "0.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
      instructions: [
        "Use Action tools to observe, resolve, act, record, and inspect native macOS surfaces.",
        "Treat action.record.start as asynchronous; completion is represented by action.record.status and the finished file.",
        "Prefer action.observe.snapshot and action.resolve.target before action.act.execute.",
      ].join("\n"),
    },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools,
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const handler = handlers[request.params.name];
    if (!handler) {
      return mcpError(`Unknown tool: ${request.params.name}`);
    }

    try {
      const args = asObject(request.params.arguments ?? {}, "arguments");
      return mcpResult(await handler(args));
    } catch (error) {
      return mcpError(error instanceof Error ? error.message : String(error), {
        tool: request.params.name,
      });
    }
  });

  return server;
}

export async function main(): Promise<void> {
  const server = createServer();
  await server.connect(new StdioServerTransport());
}

if (import.meta.main) {
  void main();
}
