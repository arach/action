#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import { mkdirSync, readFileSync, readdirSync, readlinkSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";

type JsonObject = Record<string, unknown>;

type JsonRpcRequest = {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: JsonObject;
};

type ChromeTarget = {
  id: string;
  type: string;
  title: string;
  url: string;
  webSocketDebuggerUrl?: string;
};

type ToolResult = {
  content: Array<
    | { type: "text"; text: string }
    | { type: "image"; data: string; mimeType: "image/png" }
  >;
  structuredContent?: JsonObject;
  isError?: boolean;
};

type BrowserClaim = {
  session: string;
  pid: number;
  ownerStartedAt: number;
  profile: string;
  profileDir: string;
  debugPort: number;
  claimedAt: string;
};

type ReleaseOutcome = {
  reason: string;
  closed: boolean;
  liveOwners: number;
};

const debugPort = Number(process.env.ACTION_BROWSER_DEBUG_PORT ?? "9334");
const profileName = process.env.ACTION_BROWSER_PROFILE ?? "agent-browser";
const profileDir = process.env.ACTION_BROWSER_PROFILE_DIR
  ?? join(homedir(), "Library/Application Support/Action/ChromeProfiles", profileName);
const artifactRoot = process.env.ACTION_BROWSER_ARTIFACT_DIR
  ?? join(homedir(), "Library/Application Support/Action/BrowserArtifacts");
const sessionRoot = process.env.ACTION_BROWSER_SESSION_DIR
  ?? join(homedir(), "Library/Application Support/Action/BrowserSessions");
const sessionName = (process.env.ACTION_BROWSER_SESSION
  ?? `action-${process.pid}-${Math.random().toString(36).slice(2, 8)}`)
  .replace(/[^A-Za-z0-9._-]/g, "-");
const idleTimeoutMs = Math.max(0, Number(process.env.ACTION_BROWSER_IDLE_TIMEOUT_MS ?? "900000") || 0);
const shutdownBudgetMs = Math.max(500, Number(process.env.ACTION_BROWSER_SHUTDOWN_TIMEOUT_MS ?? "4000") || 4_000);
const chromeAppName = process.env.ACTION_BROWSER_CHROME_APP ?? "Google Chrome";
const chromeBaseURL = `http://127.0.0.1:${debugPort}`;
const textDecoder = new TextDecoder();
let currentTargetId: string | undefined;
let claimHeld = false;
let ownsBrowser = false;
let shuttingDown = false;
let idleTimer: ReturnType<typeof setTimeout> | undefined;

const tools = [
  {
    name: "browser_open",
    title: "Open in Action Browser",
    description: "Open a URL in an isolated real Chrome profile. Chrome starts on demand and stays in the background by default.",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to open. https:// is added when no scheme is provided." },
        background: { type: "boolean", description: "Keep Chrome hidden in the background. Defaults to true." },
        waitMs: { type: "number", description: "Maximum time to wait for the page to become ready. Defaults to 15000." },
      },
      required: ["url"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_tabs",
    title: "List Action Browser Tabs",
    description: "List open page tabs in the isolated Action Chrome profile.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_snapshot",
    title: "Inspect Browser Page",
    description: "Read page metadata, visible text, and stable selectors for interactive elements.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id from browser_open or browser_tabs." },
        maxTextChars: { type: "number", description: "Maximum visible-text characters. Defaults to 12000." },
        maxElements: { type: "number", description: "Maximum interactive elements. Defaults to 80." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_click",
    title: "Click Browser Element",
    description: "Click a DOM element by CSS selector or visible text in the isolated Chrome page.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        selector: { type: "string", description: "Preferred CSS selector from browser_snapshot." },
        text: { type: "string", description: "Visible text fallback when a selector is unavailable." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_fill",
    title: "Fill Browser Field",
    description: "Set the value of an input, textarea, select, or contenteditable element and dispatch input/change events.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        selector: { type: "string", description: "CSS selector for the field." },
        value: { type: "string", description: "Text value to enter." },
      },
      required: ["selector", "value"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_screenshot",
    title: "Capture Browser Screenshot",
    description: "Capture the current Chrome page as a PNG, save it locally, and return the image directly to the agent.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id." },
        outputPath: { type: "string", description: "Optional absolute PNG path." },
        fullPage: { type: "boolean", description: "Capture the full document instead of the viewport. Defaults to false." },
        includeImage: { type: "boolean", description: "Include image bytes in the MCP response. Defaults to true." },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, idempotentHint: false },
  },
  {
    name: "browser_close",
    title: "Close Browser Tab or Session",
    description: "Close a tab in the isolated Action Chrome profile, or release this session's browser entirely.",
    inputSchema: {
      type: "object",
      properties: {
        tabId: { type: "string", description: "Optional tab id. Defaults to the current Action Browser tab." },
        scope: {
          type: "string",
          enum: ["tab", "browser"],
          description: "Close a single tab (default) or quit Chrome once no other live session still claims it.",
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
];

class CDPSession {
  private socket: WebSocket;
  private nextId = 1;
  private pending = new Map<number, {
    resolve: (value: JsonObject) => void;
    reject: (error: Error) => void;
  }>();

  private constructor(socket: WebSocket) {
    this.socket = socket;
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data)) as {
        id?: number;
        result?: JsonObject;
        error?: { message?: string };
      };
      if (!message.id) return;
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      this.pending.delete(message.id);
      if (message.error) {
        waiter.reject(new Error(message.error.message ?? "Chrome DevTools command failed."));
      } else {
        waiter.resolve(message.result ?? {});
      }
    });
    socket.addEventListener("close", () => {
      for (const waiter of this.pending.values()) {
        waiter.reject(new Error("Chrome DevTools connection closed."));
      }
      this.pending.clear();
    });
  }

  static async connect(url: string): Promise<CDPSession> {
    const socket = new WebSocket(url);
    await new Promise<void>((resolveConnection, reject) => {
      const timeout = setTimeout(() => reject(new Error("Timed out connecting to Chrome DevTools.")), 5_000);
      socket.addEventListener("open", () => {
        clearTimeout(timeout);
        resolveConnection();
      }, { once: true });
      socket.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error("Could not connect to Chrome DevTools."));
      }, { once: true });
    });
    return new CDPSession(socket);
  }

  call(method: string, params: JsonObject = {}): Promise<JsonObject> {
    const id = this.nextId++;
    return new Promise((resolveCall, reject) => {
      this.pending.set(id, { resolve: resolveCall, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close(): void {
    this.socket.close();
  }
}

function normalizeURL(value: string): string {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value) || value.startsWith("chrome://")) {
    return value;
  }
  return `https://${value}`;
}

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${chromeBaseURL}${path}`, init);
  if (!response.ok) {
    throw new Error(`Chrome endpoint ${path} returned ${response.status}.`);
  }
  return await response.json() as T;
}

async function chromeIsReady(): Promise<boolean> {
  try {
    await fetchJson("/json/version");
    return true;
  } catch {
    return false;
  }
}

function probe(command: string[]): string {
  try {
    const result = Bun.spawnSync(command, { stdout: "pipe", stderr: "ignore" });
    return result.success ? textDecoder.decode(result.stdout).trim() : "";
  } catch {
    return "";
  }
}

function note(event: string, detail: JsonObject = {}): void {
  try {
    process.stderr.write(`${JSON.stringify({ scope: "action-browser", session: sessionName, event, ...detail })}\n`);
  } catch {
    // A closed transport must never break shutdown.
  }
}

function processIsRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as { code?: string }).code === "EPERM";
  }
}

function processStartedAt(pid: number): number | undefined {
  const started = Date.parse(probe(["/bin/ps", "-p", String(pid), "-o", "lstart="]));
  return Number.isFinite(started) ? started : undefined;
}

function signalProcess(pid: number, signal: "SIGTERM" | "SIGKILL"): void {
  try {
    process.kill(pid, signal);
  } catch {
    // Already gone.
  }
}

const ownerStartedAt = processStartedAt(process.pid) ?? Date.now();

function pidFromSessionName(name: string): number {
  const match = /^action-(\d+)(?:-|$)/.exec(name);
  return match ? Number(match[1]) : 0;
}

function claimPath(session: string): string {
  return join(sessionRoot, `${session}.json`);
}

function readClaims(): BrowserClaim[] {
  let entries: string[];
  try {
    entries = readdirSync(sessionRoot);
  } catch {
    return [];
  }
  const claims: BrowserClaim[] = [];
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue;
    const session = entry.slice(0, -".json".length);
    try {
      const claim = JSON.parse(readFileSync(join(sessionRoot, entry), "utf8")) as Partial<BrowserClaim>;
      const pid = Number.isInteger(claim.pid) ? Number(claim.pid) : pidFromSessionName(session);
      if (pid <= 0) throw new Error("Claim has no resolvable owner pid.");
      claims.push({
        session,
        pid,
        ownerStartedAt: Number(claim.ownerStartedAt),
        profile: String(claim.profile ?? profileName),
        profileDir: String(claim.profileDir ?? profileDir),
        debugPort: Number(claim.debugPort ?? debugPort),
        claimedAt: String(claim.claimedAt ?? ""),
      });
    } catch {
      try {
        unlinkSync(join(sessionRoot, entry));
      } catch {
        // Another session may have swept it already.
      }
    }
  }
  return claims;
}

function ownerIsAlive(claim: BrowserClaim): boolean {
  if (!processIsRunning(claim.pid)) return false;
  if (!Number.isFinite(claim.ownerStartedAt)) return true;
  const startedAt = processStartedAt(claim.pid);
  return startedAt === undefined || startedAt <= claim.ownerStartedAt + 2_000;
}

function claimTargetsThisBrowser(claim: BrowserClaim): boolean {
  return claim.profileDir === profileDir && claim.debugPort === debugPort;
}

function claimBrowser(): void {
  if (claimHeld || shuttingDown) return;
  const claim: BrowserClaim = {
    session: sessionName,
    pid: process.pid,
    ownerStartedAt,
    profile: profileName,
    profileDir,
    debugPort,
    claimedAt: new Date().toISOString(),
  };
  try {
    mkdirSync(sessionRoot, { recursive: true });
    const staging = join(sessionRoot, `.${sessionName}.tmp`);
    writeFileSync(staging, `${JSON.stringify(claim, null, 2)}\n`);
    renameSync(staging, claimPath(sessionName));
    claimHeld = true;
    ownsBrowser = true;
    note("claim", { pid: process.pid, profileDir, debugPort });
  } catch {
    // Losing the registry must not block browser work.
  }
}

function releaseClaim(): void {
  claimHeld = false;
  try {
    unlinkSync(claimPath(sessionName));
  } catch {
    // Nothing to release.
  }
}

function sweepClaims(): { liveOwners: number; staleOwners: number } {
  let liveOwners = 0;
  let staleOwners = 0;
  for (const claim of readClaims()) {
    if (claim.session === sessionName) continue;
    if (ownerIsAlive(claim)) {
      if (claimTargetsThisBrowser(claim)) liveOwners += 1;
      continue;
    }
    if (claimTargetsThisBrowser(claim)) staleOwners += 1;
    try {
      unlinkSync(claimPath(claim.session));
    } catch {
      // Another session may have swept it already.
    }
  }
  return { liveOwners, staleOwners };
}

function chromeProcessId(): number | undefined {
  let link: string;
  try {
    link = readlinkSync(join(profileDir, "SingletonLock"));
  } catch {
    return undefined;
  }
  const pid = Number(link.slice(link.lastIndexOf("-") + 1));
  if (!Number.isInteger(pid) || pid <= 1) return undefined;
  return probe(["/bin/ps", "-p", String(pid), "-o", "command="]).includes(`--user-data-dir=${profileDir}`)
    ? pid
    : undefined;
}

async function closeChrome(): Promise<boolean> {
  const chromePid = chromeProcessId();
  try {
    const version = await fetchJson<{ webSocketDebuggerUrl?: string }>("/json/version");
    if (version.webSocketDebuggerUrl) {
      const session = await CDPSession.connect(version.webSocketDebuggerUrl);
      await Promise.race([session.call("Browser.close").catch(() => {}), Bun.sleep(1_500)]);
      session.close();
    }
  } catch {
    // Chrome is unreachable; fall through to the signal ladder.
  }
  if (chromePid === undefined) return !(await chromeIsReady());
  for (let attempt = 0; attempt < 24; attempt += 1) {
    if (!processIsRunning(chromePid)) return true;
    if (attempt === 2) signalProcess(chromePid, "SIGTERM");
    if (attempt === 16) signalProcess(chromePid, "SIGKILL");
    await Bun.sleep(125);
  }
  return !processIsRunning(chromePid);
}

async function releaseBrowser(reason: string): Promise<ReleaseOutcome> {
  releaseClaim();
  const { liveOwners } = sweepClaims();
  if (liveOwners > 0) {
    ownsBrowser = false;
    return { reason, closed: false, liveOwners };
  }
  const closed = await closeChrome();
  if (closed) ownsBrowser = false;
  return { reason, closed, liveOwners };
}

async function releaseOwnedBrowser(reason: string): Promise<ReleaseOutcome | undefined> {
  return ownsBrowser ? await releaseBrowser(reason) : undefined;
}

function releaseBrowserSync(): void {
  if (!ownsBrowser) return;
  releaseClaim();
  if (sweepClaims().liveOwners > 0) return;
  const chromePid = chromeProcessId();
  if (chromePid !== undefined) signalProcess(chromePid, "SIGTERM");
}

async function sweepOrphans(): Promise<void> {
  const { liveOwners, staleOwners } = sweepClaims();
  if (staleOwners === 0 || liveOwners > 0) return;
  if (chromeProcessId() === undefined && !(await chromeIsReady())) return;
  const closed = await closeChrome();
  note("sweep", { staleOwners, closed });
}

function scheduleIdleRelease(): void {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = undefined;
  if (idleTimeoutMs <= 0 || shuttingDown) return;
  const timer = setTimeout(() => {
    void releaseOwnedBrowser("idle").then((outcome) => {
      if (outcome) note("idle", outcome);
    });
  }, idleTimeoutMs);
  timer.unref();
  idleTimer = timer;
}

async function shutdown(reason: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  if (idleTimer) clearTimeout(idleTimer);
  const owned = ownsBrowser;
  const outcome = await Promise.race([
    releaseOwnedBrowser(reason),
    Bun.sleep(shutdownBudgetMs).then(() => undefined),
  ]);
  note("shutdown", { reason, owned, closed: outcome?.closed ?? false, timedOut: owned && outcome === undefined });
  process.exit(0);
}

function installLifecycleHooks(): void {
  for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"] as const) {
    process.on(signal, () => {
      void shutdown(signal);
    });
  }
  process.on("exit", () => {
    releaseBrowserSync();
  });
}

async function ensureChrome(background = true): Promise<void> {
  if (await chromeIsReady()) {
    claimBrowser();
    return;
  }

  await mkdir(profileDir, { recursive: true });
  const openArgs = [
    "/usr/bin/open",
    "-n",
    "-a",
    chromeAppName,
  ];
  if (background) {
    openArgs.push("-j", "-g");
  }
  openArgs.push(
    "--args",
    `--user-data-dir=${profileDir}`,
    `--remote-debugging-port=${debugPort}`,
    "--remote-allow-origins=*",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--window-size=1440,1000",
    "about:blank",
  );

  const launch = Bun.spawn(openArgs, { stdout: "ignore", stderr: "pipe" });
  const status = await launch.exited;
  if (status !== 0) {
    const stderr = await new Response(launch.stderr).text();
    throw new Error(stderr.trim() || `Could not launch ${chromeAppName}.`);
  }

  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (await chromeIsReady()) {
      claimBrowser();
      return;
    }
    await Bun.sleep(250);
  }

  throw new Error(`Chrome did not expose its local debugging port at ${chromeBaseURL}.`);
}

async function listTargets(): Promise<ChromeTarget[]> {
  await ensureChrome();
  return (await fetchJson<ChromeTarget[]>("/json/list"))
    .filter((target) => target.type === "page" && Boolean(target.webSocketDebuggerUrl));
}

async function targetFor(tabId?: unknown): Promise<ChromeTarget> {
  const targets = await listTargets();
  const requestedId = typeof tabId === "string" ? tabId : currentTargetId;
  const target = requestedId
    ? targets.find((candidate) => candidate.id === requestedId)
    : targets.find((candidate) => !candidate.url.startsWith("chrome://")) ?? targets[0];
  if (!target?.webSocketDebuggerUrl) {
    throw new Error("No Action Browser tab is available. Call browser_open first.");
  }
  currentTargetId = target.id;
  return target;
}

async function withTarget<T>(tabId: unknown, work: (session: CDPSession, target: ChromeTarget) => Promise<T>): Promise<T> {
  const target = await targetFor(tabId);
  const session = await CDPSession.connect(target.webSocketDebuggerUrl!);
  try {
    return await work(session, target);
  } finally {
    session.close();
  }
}

async function waitUntilReady(session: CDPSession, timeoutMs: number): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const result = await session.call("Runtime.evaluate", {
      expression: "({ state: document.readyState, url: location.href })",
      returnByValue: true,
    });
    const value = (result.result as JsonObject | undefined)?.value as JsonObject | undefined;
    const state = value?.state;
    const url = value?.url;
    if (
      (state === "complete" || state === "interactive")
      && typeof url === "string"
      && url !== "about:blank"
    ) return;
    await Bun.sleep(150);
  }
}

async function evaluateValue(session: CDPSession, expression: string): Promise<unknown> {
  const response = await session.call("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });
  const exception = response.exceptionDetails as JsonObject | undefined;
  if (exception) {
    throw new Error(String(exception.text ?? "Page evaluation failed."));
  }
  return (response.result as JsonObject | undefined)?.value;
}

function asString(value: unknown, label: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

function stringValue(value: unknown, label: string): string {
  if (typeof value !== "string") {
    throw new Error(`${label} is required.`);
  }
  return value;
}

function optionalNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function textResult(data: JsonObject): ToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    structuredContent: data,
  };
}

async function callTool(name: string, args: JsonObject): Promise<ToolResult> {
  switch (name) {
    case "browser_open": {
      const url = normalizeURL(asString(args.url, "url"));
      const background = args.background !== false;
      await ensureChrome(background);
      const target = await fetchJson<ChromeTarget>("/json/new?about%3Ablank", { method: "PUT" });
      if (!target.webSocketDebuggerUrl) {
        throw new Error("Chrome created a tab without a DevTools endpoint.");
      }
      currentTargetId = target.id;
      const session = await CDPSession.connect(target.webSocketDebuggerUrl);
      try {
        await session.call("Page.enable");
        await session.call("Page.navigate", { url });
        await waitUntilReady(session, optionalNumber(args.waitMs, 15_000));
        const page = await evaluateValue(session, "({ title: document.title, url: location.href })") as JsonObject;
        return textResult({
          ok: true,
          tab: { id: target.id, title: page.title ?? target.title, url: page.url ?? url },
          chrome: { profile: profileName, background, debugPort, session: sessionName },
        });
      } finally {
        session.close();
      }
    }

    case "browser_tabs": {
      const tabs = (await listTargets()).map(({ id, title, url }) => ({
        id,
        title,
        url,
        current: id === currentTargetId,
      }));
      return textResult({ ok: true, tabs });
    }

    case "browser_snapshot":
      return await withTarget(args.tabId, async (session, target) => {
        const maxTextChars = Math.max(500, optionalNumber(args.maxTextChars, 12_000));
        const maxElements = Math.max(1, optionalNumber(args.maxElements, 80));
        const expression = `(() => {
          const visible = (element) => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
          };
          const selector = (element) => {
            if (element.id) return "#" + CSS.escape(element.id);
            const testId = element.getAttribute("data-testid");
            if (testId) return '[data-testid="' + CSS.escape(testId) + '"]';
            const name = element.getAttribute("name");
            if (name) return element.tagName.toLowerCase() + '[name="' + CSS.escape(name) + '"]';
            const role = element.getAttribute("role");
            if (role) return element.tagName.toLowerCase() + '[role="' + CSS.escape(role) + '"]';
            return element.tagName.toLowerCase();
          };
          const nodes = [...document.querySelectorAll('a[href],button,input,select,textarea,[role],[contenteditable="true"],[tabindex]')]
            .filter(visible)
            .slice(0, ${maxElements})
            .map((element) => {
              const rect = element.getBoundingClientRect();
              const isPassword = element instanceof HTMLInputElement && element.type === "password";
              return {
                selector: selector(element),
                tag: element.tagName.toLowerCase(),
                role: element.getAttribute("role"),
                label: element.getAttribute("aria-label") || element.getAttribute("placeholder") || element.innerText?.trim() || element.getAttribute("name"),
                value: isPassword ? null : ("value" in element ? String(element.value).slice(0, 500) : null),
                rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
              };
            });
          return {
            title: document.title,
            url: location.href,
            text: (document.body?.innerText || "").replace(/\\s+/g, " ").trim().slice(0, ${maxTextChars}),
            elements: nodes
          };
        })()`;
        const snapshot = await evaluateValue(session, expression) as JsonObject;
        return textResult({ ok: true, tabId: target.id, ...snapshot });
      });

    case "browser_click":
      return await withTarget(args.tabId, async (session, target) => {
        const selector = typeof args.selector === "string" ? args.selector : undefined;
        const text = typeof args.text === "string" ? args.text : undefined;
        if (!selector && !text) throw new Error("browser_click requires selector or text.");
        const expression = `(() => {
          const selector = ${JSON.stringify(selector)};
          const text = ${JSON.stringify(text?.trim().toLowerCase())};
          const candidates = [...document.querySelectorAll('a[href],button,input,[role="button"],[role="link"],[tabindex]')];
          const element = selector
            ? document.querySelector(selector)
            : candidates.find((candidate) => (candidate.innerText || candidate.textContent || candidate.getAttribute("aria-label") || "").trim().toLowerCase().includes(text));
          if (!(element instanceof HTMLElement)) throw new Error("No clickable element matched.");
          element.scrollIntoView({ block: "center", inline: "center" });
          element.click();
          return { selector: selector || element.tagName.toLowerCase(), text: (element.innerText || element.textContent || "").trim().slice(0, 300) };
        })()`;
        const result = await evaluateValue(session, expression) as JsonObject;
        await Bun.sleep(250);
        return textResult({ ok: true, tabId: target.id, result });
      });

    case "browser_fill":
      return await withTarget(args.tabId, async (session, target) => {
        const selector = asString(args.selector, "selector");
        const value = stringValue(args.value, "value");
        const expression = `(() => {
          const element = document.querySelector(${JSON.stringify(selector)});
          if (!(element instanceof HTMLElement)) throw new Error("No field matched the selector.");
          if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement) {
            const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element), "value")?.set;
            setter ? setter.call(element, ${JSON.stringify(value)}) : element.value = ${JSON.stringify(value)};
          } else if (element.isContentEditable) {
            element.textContent = ${JSON.stringify(value)};
          } else {
            throw new Error("Matched element is not editable.");
          }
          element.focus();
          element.dispatchEvent(new InputEvent("input", { bubbles: true, data: ${JSON.stringify(value)}, inputType: "insertText" }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return { selector: ${JSON.stringify(selector)}, valueLength: ${value.length} };
        })()`;
        const result = await evaluateValue(session, expression) as JsonObject;
        return textResult({ ok: true, tabId: target.id, result });
      });

    case "browser_screenshot":
      return await withTarget(args.tabId, async (session, target) => {
        await session.call("Page.enable");
        const fullPage = args.fullPage === true;
        let captureParams: JsonObject = {
          format: "png",
          fromSurface: true,
          captureBeyondViewport: fullPage,
        };
        if (fullPage) {
          const metrics = await session.call("Page.getLayoutMetrics");
          const contentSize = metrics.cssContentSize as JsonObject | undefined
            ?? metrics.contentSize as JsonObject | undefined;
          if (contentSize) {
            captureParams = {
              ...captureParams,
              clip: {
                x: 0,
                y: 0,
                width: Math.min(Number(contentSize.width ?? 1440), 16_384),
                height: Math.min(Number(contentSize.height ?? 1000), 16_384),
                scale: 1,
              },
            };
          }
        }
        const capture = await session.call("Page.captureScreenshot", captureParams);
        const data = asString(capture.data, "screenshot data");
        const requestedPath = typeof args.outputPath === "string" ? args.outputPath : undefined;
        if (requestedPath && !isAbsolute(requestedPath)) {
          throw new Error("outputPath must be absolute when provided.");
        }
        const outputPath = requestedPath
          ? resolve(requestedPath)
          : join(artifactRoot, `browser-${new Date().toISOString().replace(/[:.]/g, "-")}.png`);
        await mkdir(dirname(outputPath), { recursive: true });
        await Bun.write(outputPath, Buffer.from(data, "base64"));
        const metadata: JsonObject = {
          ok: true,
          tabId: target.id,
          title: target.title,
          url: target.url,
          outputPath,
          fullPage,
          mimeType: "image/png",
        };
        return {
          content: [
            { type: "text", text: JSON.stringify(metadata, null, 2) },
            ...(args.includeImage === false ? [] : [{ type: "image" as const, data, mimeType: "image/png" as const }]),
          ],
          structuredContent: metadata,
        };
      });

    case "browser_close": {
      if (args.scope === "browser") {
        const outcome = await releaseBrowser("browser_close");
        currentTargetId = undefined;
        return textResult({
          ok: true,
          scope: "browser",
          session: sessionName,
          closed: outcome.closed,
          liveOwners: outcome.liveOwners,
        });
      }
      const target = await targetFor(args.tabId);
      const response = await fetch(`${chromeBaseURL}/json/close/${encodeURIComponent(target.id)}`);
      if (!response.ok) {
        throw new Error(`Chrome could not close tab ${target.id}.`);
      }
      if (currentTargetId === target.id) currentTargetId = undefined;
      return textResult({ ok: true, closed: target.id });
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

async function handleRequest(request: JsonRpcRequest): Promise<JsonObject | undefined> {
  const id = request.id;
  if (request.method.startsWith("notifications/") || id === undefined) {
    return undefined;
  }

  try {
    switch (request.method) {
      case "initialize":
        return {
          jsonrpc: "2.0",
          id,
          result: {
            protocolVersion: String(request.params?.protocolVersion ?? "2025-06-18"),
            capabilities: { tools: { listChanged: false } },
            serverInfo: { name: "action-browser", version: "0.1.0" },
            instructions: "Use browser_open, then browser_screenshot for the fastest URL-to-image workflow in a real Chrome profile.",
          },
        };
      case "ping":
        return { jsonrpc: "2.0", id, result: {} };
      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools } };
      case "tools/call": {
        scheduleIdleRelease();
        const params = request.params ?? {};
        const name = asString(params.name, "tool name");
        const args = params.arguments && typeof params.arguments === "object"
          ? params.arguments as JsonObject
          : {};
        return { jsonrpc: "2.0", id, result: await callTool(name, args) };
      }
      default:
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: `Method not found: ${request.method}` },
        };
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (request.method === "tools/call") {
      return {
        jsonrpc: "2.0",
        id,
        result: {
          isError: true,
          content: [{ type: "text", text: JSON.stringify({ ok: false, error: message }, null, 2) }],
          structuredContent: { ok: false, error: message },
        },
      };
    }
    return { jsonrpc: "2.0", id, error: { code: -32603, message } };
  }
}

async function main(): Promise<void> {
  installLifecycleHooks();
  await sweepOrphans();

  let buffer = "";
  const decoder = new TextDecoder();

  for await (const chunk of Bun.stdin.stream()) {
    buffer += decoder.decode(chunk, { stream: true });
    while (buffer.includes("\n")) {
      const newline = buffer.indexOf("\n");
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      const request = JSON.parse(line) as JsonRpcRequest;
      const response = await handleRequest(request);
      if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
    }
  }

  await shutdown("stdin-eof");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
