import { readFile } from "node:fs/promises"

import type { Bounds, Point } from "@action/protocol"
import { Client } from "@modelcontextprotocol/sdk/client"
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js"

import type { CurrentSurfaceSnapshot } from "../macos.js"

export interface ViewportSettleDragInstruction {
  from: Point
  to: Point
  durationMs?: number
}

export interface ViewportSettleProviderRequest {
  kind: "viewport-settle"
  sessionId: string
  turn: number
  maxTurns: number
  provider: string
  model: string
  screenshotPath: string
  axSnapshotPath?: string
  targetViewport: Bounds
  currentBounds?: Bounds
  currentSurface: CurrentSurfaceSnapshot
  prompt: string
  metadata?: Record<string, unknown>
}

export interface ViewportSettleProviderResponse {
  status: "drag" | "done"
  summary: string
  confidence?: number
  observedBounds?: Bounds
  drag?: ViewportSettleDragInstruction
  titleBarPoint?: Point
  targetPoint?: Point
  rationale?: string
  metadata?: Record<string, unknown>
  raw?: unknown
}

export interface ViewportSettleProvider {
  readonly id: string
  analyzeViewportTurn(
    request: ViewportSettleProviderRequest,
  ): Promise<ViewportSettleProviderResponse>
}

export interface PieMinimaxViewportSettleProviderOptions {
  command?: string
  args?: string[]
  model?: string
  timeoutMs?: number
  env?: NodeJS.ProcessEnv
}

function defaultPrompt(): string {
  return [
    "You are aligning one macOS app window into a target viewport for demo capture.",
    "Look at the screenshot and decide whether the target app window already fits the requested viewport.",
    "If it is already aligned closely enough, respond with status=done.",
    "If it must move, respond with status=drag and provide:",
    "- observedBounds for the app window in screen coordinates",
    "- a drag.from point on the title bar of the window",
    "- a drag.to point that would move the window closer to the requested viewport",
    "Return only JSON. Do not include markdown.",
  ].join("\n")
}

function parseArgsJSON(input: string | undefined): string[] {
  if (!input) {
    return []
  }

  const parsed = JSON.parse(input) as unknown
  if (!Array.isArray(parsed) || parsed.some((value) => typeof value !== "string")) {
    throw new Error("ACTION_PIE_ARGS_JSON must be a JSON string array")
  }

  return parsed as string[]
}

function envRecord(env: NodeJS.ProcessEnv): Record<string, string> {
  const record: Record<string, string> = {}
  for (const [key, value] of Object.entries(env)) {
    if (typeof value === "string") {
      record[key] = value
    }
  }
  return record
}

function asObject(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Viewport settle provider response must be a JSON object")
  }

  return input as Record<string, unknown>
}

function parsePoint(input: unknown, label: string): Point {
  const object = asObject(input)
  const x = object.x
  const y = object.y
  if (typeof x !== "number" || typeof y !== "number") {
    throw new Error(`Viewport settle provider ${label} must include numeric x/y`)
  }
  return { x, y }
}

function parseBounds(input: unknown): Bounds {
  const object = asObject(input)
  const x = object.x
  const y = object.y
  const width = object.width
  const height = object.height
  if (
    typeof x !== "number"
    || typeof y !== "number"
    || typeof width !== "number"
    || typeof height !== "number"
  ) {
    throw new Error("Viewport settle provider observedBounds must include numeric x/y/width/height")
  }
  return { x, y, width, height }
}

function normalizeProviderResponse(input: unknown): ViewportSettleProviderResponse {
  const object = asObject(input)
  const status = object.status
  const summary = object.summary

  if (status !== "drag" && status !== "done") {
    throw new Error("Viewport settle provider response status must be 'drag' or 'done'")
  }

  if (typeof summary !== "string" || summary.length === 0) {
    throw new Error("Viewport settle provider response summary must be a non-empty string")
  }

  const response: ViewportSettleProviderResponse = {
    status,
    summary,
    raw: input,
  }

  if (typeof object.confidence === "number") {
    response.confidence = object.confidence
  }

  if (object.observedBounds !== undefined) {
    response.observedBounds = parseBounds(object.observedBounds)
  }

  if (object.titleBarPoint !== undefined) {
    response.titleBarPoint = parsePoint(object.titleBarPoint, "titleBarPoint")
  }

  if (object.targetPoint !== undefined) {
    response.targetPoint = parsePoint(object.targetPoint, "targetPoint")
  }

  if (typeof object.rationale === "string" && object.rationale.length > 0) {
    response.rationale = object.rationale
  }

  if (object.metadata && typeof object.metadata === "object" && !Array.isArray(object.metadata)) {
    response.metadata = object.metadata as Record<string, unknown>
  }

  if (status === "drag") {
    const dragObject = asObject(object.drag)
    response.drag = {
      from: parsePoint(dragObject.from, "drag.from"),
      to: parsePoint(dragObject.to, "drag.to"),
      durationMs: typeof dragObject.durationMs === "number" ? dragObject.durationMs : undefined,
    }
  }

  return response
}

async function readAxSummary(path: string | undefined): Promise<unknown[] | undefined> {
  if (!path) {
    return undefined
  }

  try {
    const raw = await readFile(path, "utf8")
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) {
      return undefined
    }

    return parsed.slice(0, 18)
  } catch {
    return undefined
  }
}

function buildAnalysisPrompt(request: ViewportSettleProviderRequest, axSummary?: unknown[]): string {
  const context = {
    targetViewport: request.targetViewport,
    currentBounds: request.currentBounds ?? null,
    currentSurface: {
      appName: request.currentSurface.appName,
      bundleId: request.currentSurface.bundleId,
      surfaceId: request.currentSurface.surface.id,
      surfaceBounds: request.currentSurface.surface.bounds,
      windowLabel: request.currentSurface.surface.label,
    },
    axSummary: axSummary ?? null,
  }

  return [
    request.prompt || defaultPrompt(),
    "",
    "Use screenshot pixel coordinates with origin at the top-left corner of the image.",
    "Prefer a single title-bar drag that moves the whole window toward the viewport.",
    "If the window already overlaps the target viewport closely enough for demo capture, respond with status=done.",
    "Return exactly one JSON object with this shape:",
    JSON.stringify({
      status: "done",
      summary: "Window is aligned",
      confidence: 0.92,
      observedBounds: {
        x: 0,
        y: 0,
        width: 100,
        height: 100,
      },
    }, null, 2),
    "or",
    JSON.stringify({
      status: "drag",
      summary: "Move the window left and slightly down",
      confidence: 0.81,
      observedBounds: {
        x: 0,
        y: 0,
        width: 100,
        height: 100,
      },
      drag: {
        from: { x: 50, y: 20 },
        to: { x: 20, y: 40 },
        durationMs: 260,
      },
      titleBarPoint: { x: 50, y: 20 },
      targetPoint: { x: 20, y: 40 },
      rationale: "Title bar sits to the right of the target viewport",
    }, null, 2),
    "",
    "Viewport-settle context:",
    JSON.stringify(context, null, 2),
  ].join("\n")
}

function stripCodeFence(input: string): string {
  const fencedMatch = input.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i)
  if (fencedMatch) {
    return fencedMatch[1].trim()
  }

  return input.trim()
}

function extractJSONObject(input: string): string {
  const trimmed = stripCodeFence(input)
  const start = trimmed.indexOf("{")
  const end = trimmed.lastIndexOf("}")
  if (start === -1 || end === -1 || end < start) {
    throw new Error("Viewport settle provider did not return a JSON object")
  }

  return trimmed.slice(start, end + 1)
}

function parseJSONText(input: string): unknown {
  const candidate = extractJSONObject(input)
  return JSON.parse(candidate) as unknown
}

function extractTextResult(result: unknown): string {
  const object = asObject(result)
  let content = object.content

  if (!Array.isArray(content) && object.toolResult !== undefined) {
    const toolResult = asObject(object.toolResult)
    content = toolResult.content
  }

  if (!Array.isArray(content)) {
    throw new Error("MiniMax MCP returned no content payload for viewport settle")
  }

  const text = content
    .filter((item): item is { type: string; text?: string } => {
      return !!item && typeof item === "object" && !Array.isArray(item)
    })
    .filter((item) => item.type === "text" && typeof item.text === "string")
    .map((item) => item.text ?? "")
    .join("\n")
    .trim()

  if (text.length === 0) {
    throw new Error("MiniMax MCP returned no text content for viewport settle")
  }

  return text
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => {
          reject(new Error(`${label} timed out after ${timeoutMs}ms`))
        }, timeoutMs)
      }),
    ])
  } finally {
    if (timer) {
      clearTimeout(timer)
    }
  }
}

export class MockViewportSettleProvider implements ViewportSettleProvider {
  readonly id = "mock"

  async analyzeViewportTurn(
    request: ViewportSettleProviderRequest,
  ): Promise<ViewportSettleProviderResponse> {
    return {
      status: "done",
      summary: `Mock settle accepted viewport on turn ${request.turn}`,
      confidence: 1,
      observedBounds: request.currentBounds ?? request.targetViewport,
      metadata: {
        mock: true,
      },
      raw: {
        status: "done",
        summary: `Mock settle accepted viewport on turn ${request.turn}`,
      },
    }
  }
}

export class PieMinimaxViewportSettleProvider implements ViewportSettleProvider {
  readonly id: string
  readonly model: string
  readonly command: string
  readonly args: string[]
  readonly timeoutMs: number
  readonly env: NodeJS.ProcessEnv

  constructor(options: PieMinimaxViewportSettleProviderOptions = {}) {
    const env = options.env ?? process.env
    const model = options.model ?? env.ACTION_PIE_MODEL ?? "minimax-m2.7"
    const command = options.command ?? env.ACTION_PIE_COMMAND ?? "uvx"
    const args = options.args ?? parseArgsJSON(env.ACTION_PIE_ARGS_JSON)
    const resolvedArgs = args.length > 0 ? args : ["minimax-coding-plan-mcp", "-y"]

    this.model = model
    this.command = command
    this.args = resolvedArgs
    this.timeoutMs = options.timeoutMs ?? Number(env.ACTION_PIE_TIMEOUT_MS ?? 20000)
    this.env = env
    this.id = `pie:${model}`
  }

  async analyzeViewportTurn(
    request: ViewportSettleProviderRequest,
  ): Promise<ViewportSettleProviderResponse> {
    const apiKey = this.env.MINIMAX_API_KEY
    if (!apiKey) {
      throw new Error("MINIMAX_API_KEY is required for the MiniMax viewport-settle provider")
    }

    const axSummary = await readAxSummary(request.axSnapshotPath)
    const prompt = buildAnalysisPrompt(request, axSummary)
    const stderrLines: string[] = []
    const transport = new StdioClientTransport({
      command: this.command,
      args: this.args,
      env: {
        ...envRecord(this.env),
        MINIMAX_API_KEY: apiKey,
        MINIMAX_API_HOST: this.env.MINIMAX_API_HOST ?? "https://api.minimax.io",
      },
      stderr: "pipe",
    })
    const stderr = transport.stderr
    if (stderr) {
      stderr.on("data", (chunk: Buffer | string) => {
        const line = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk)
        stderrLines.push(line)
      })
    }

    const client = new Client(
      { name: "action-runtime", version: "0.0.0" },
      { capabilities: {} },
    )

    try {
      await withTimeout(client.connect(transport), this.timeoutMs, "MiniMax MCP connect")

      const toolResult = await withTimeout(
        client.callTool({
          name: "understand_image",
          arguments: {
            prompt,
            image_source: request.screenshotPath,
          },
        }),
        this.timeoutMs,
        "MiniMax understand_image",
      )
      const text = extractTextResult(toolResult)
      const parsed = parseJSONText(text)
      const normalized = normalizeProviderResponse(parsed)
      normalized.raw = {
        provider: this.id,
        model: this.model,
        text,
        parsed,
      }
      return normalized
    } catch (error) {
      const stderrText = stderrLines.join("").trim()
      const suffix = stderrText.length > 0 ? `\n${stderrText}` : ""
      throw new Error(`MiniMax viewport-settle failed: ${errorMessage(error)}${suffix}`)
    } finally {
      await transport.close().catch(() => {})
    }
  }
}

export function createViewportSettleProvider(
  providerId: "mock" | "pie-minimax" = "pie-minimax",
  options: PieMinimaxViewportSettleProviderOptions = {},
): ViewportSettleProvider {
  if (providerId === "mock") {
    return new MockViewportSettleProvider()
  }

  return new PieMinimaxViewportSettleProvider(options)
}

export function viewportSettlePrompt(): string {
  return defaultPrompt()
}
