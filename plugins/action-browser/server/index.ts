#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assessNavigation,
  browserOpenMode,
  navigationIsReady,
  regularChromeLaunchArgs,
  shouldReuseCurrentTab,
} from "./navigation.ts";

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
const profileRoot = process.env.ACTION_BROWSER_PROFILE_ROOT
  ?? process.env.ACTION_CHROME_COMPANION_PROFILE_ROOT
  ?? join(homedir(), "Library/Application Support/Action/ChromeProfiles");
const fixedProfileDir = process.env.ACTION_BROWSER_PROFILE_DIR
  ?? process.env.ACTION_CHROME_COMPANION_PROFILE_DIR;
let profileName = sanitizeProfileName(
  process.env.ACTION_BROWSER_PROFILE
    ?? process.env.ACTION_CHROME_COMPANION_PROFILE
    ?? "agent-browser",
);
let profileDir = fixedProfileDir ?? join(profileRoot, profileName);
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
const companionBridgeHealthURL = process.env.ACTION_CHROME_COMPANION_HEALTH_URL
  ?? "http://127.0.0.1:4321/health";
const textDecoder = new TextDecoder();
let currentTargetId: string | undefined;
let claimHeld = false;
let ownsBrowser = false;
let shuttingDown = false;
let idleTimer: ReturnType<typeof setTimeout> | undefined;

function sanitizeProfileName(name: string): string {
  const cleaned = name.trim().replace(/[^A-Za-z0-9._-]/g, "-");
  if (!cleaned || cleaned === "." || cleaned === "..") {
    throw new Error(`Invalid Action profile name: ${name}`);
  }
  return cleaned;
}

function resolveActionRoot(): string {
  if (process.env.ACTION_ROOT) return resolve(process.env.ACTION_ROOT);
  // plugins/action-browser/server -> repo root
  return resolve(fileURLToPath(new URL("../../..", import.meta.url)));
}

function companionScriptsDir(): string {
  return join(resolveActionRoot(), "packages/chrome-companion/scripts");
}

function companionDistDir(): string {
  return join(resolveActionRoot(), "packages/chrome-companion/dist");
}

function writeProfileMeta(name: string, dir: string): void {
  try {
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      join(dir, ".action-profile.json"),
      `${JSON.stringify({
        name,
        profileDir: dir,
        extensionDist: companionDistDir(),
        debugPort,
        updatedAt: new Date().toISOString(),
      }, null, 2)}\n`,
    );
  } catch {
    // Metadata is best-effort.
  }
}

function listActionProfilesOnDisk(): Array<{
  name: string;
  userDataDir: string;
  current: boolean;
  hasCookiesDb: boolean;
  meta: JsonObject | null;
}> {
  if (!existsSync(profileRoot)) return [];
  return readdirSync(profileRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => {
      const userDataDir = join(profileRoot, entry.name);
      const defaultDir = existsSync(join(userDataDir, "Cookies"))
        ? userDataDir
        : join(userDataDir, "Default");
      const metaPath = join(userDataDir, ".action-profile.json");
      let meta: JsonObject | null = null;
      if (existsSync(metaPath)) {
        try {
          meta = JSON.parse(readFileSync(metaPath, "utf8")) as JsonObject;
        } catch {
          meta = null;
        }
      }
      return {
        name: entry.name,
        userDataDir,
        current: userDataDir === profileDir,
        hasCookiesDb: existsSync(join(defaultDir, "Cookies")),
        meta,
      };
    })
    .sort((left, right) => left.name.localeCompare(right.name));
}

async function loadCookieModule(): Promise<{
  importCookiesToActionProfile: (args: {
    into?: string;
    sourceProfile?: string;
    domains?: string[];
    selectors?: Array<{ hostKey?: string; name: string }>;
  }) => {
    into: string;
    sourceProfilePath: string;
    destUserDataDir: string;
    destProfilePath: string;
    cookies: string[];
    count: number;
  };
  listCookieEntries: (
    profileDir: string,
    opts: { domains?: string[]; selectors?: Array<{ hostKey?: string; name: string }> },
  ) => Array<{ hostKey: string; name: string }>;
  listPersonalProfiles: () => Array<{ dir: string; name: string; path: string }>;
  parseCookieSelectors: (specs: string[]) => Array<{ hostKey?: string; name: string }>;
  resolveSourceProfileDir: (profileDir?: string) => string;
}> {
  const modulePath = join(companionScriptsDir(), "chrome-cookies.mjs");
  if (!existsSync(modulePath)) {
    throw new Error(
      `Cookie tooling not found at ${modulePath}. ` +
      "Set ACTION_ROOT to the Action monorepo root when using the marketplace plugin outside the repo.",
    );
  }
  return await import(modulePath);
}

const tools = [
  {
    name: "browser_profiles",
    title: "List Action Browser Profiles",
    description: "List named Action-owned Chrome identities under ChromeProfiles, plus the currently active profile. These are not your daily Chrome profiles.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_use_profile",
    title: "Use Action Browser Profile",
    description: "Switch the active Action Chrome identity (named profile under ChromeProfiles). Closes the previous Action Chrome if it was owned by this session. Does not attach to daily personal Chrome.",
    inputSchema: {
      type: "object",
      properties: {
        profile: {
          type: "string",
          description: "Action profile name, e.g. agent-browser, coding, mira.",
        },
      },
      required: ["profile"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: true },
  },
  {
    name: "browser_profile_info",
    title: "Current Browser Profile Info",
    description: "Report the active Action profile path, cookies readiness, companion extension dist, and optional companion bridge health.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_import_cookies",
    title: "Import Cookies Into Action Profile",
    description: "Selectively copy cookies from personal Chrome into a named Action profile. Dry-run unless confirm=true. Prefer domain allowlists; never dumps the full jar by default.",
    inputSchema: {
      type: "object",
      properties: {
        into: {
          type: "string",
          description: "Target Action profile name. Defaults to the active profile.",
        },
        source: {
          type: "string",
          description: "Personal Chrome profile directory name (Default, Profile 1, ...). Defaults to most recently used.",
        },
        domains: {
          type: "array",
          items: { type: "string" },
          description: "Host suffixes to import, e.g. [\"github.com\", \"midjourney.com\"].",
        },
        only: {
          type: "array",
          items: { type: "string" },
          description: "Optional cookie names or host:name selectors.",
        },
        confirm: {
          type: "boolean",
          description: "When true, write cookies. When false/omitted, list matches only.",
        },
        listSourceProfiles: {
          type: "boolean",
          description: "When true, list personal Chrome profiles and return.",
        },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_companion_status",
    title: "Chrome Companion Status",
    description: "Check whether the Action Chrome Companion extension dist exists and whether the localhost bridge reports a live connection for richer DOM act/observe.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, idempotentHint: true },
  },
  {
    name: "browser_open",
    title: "Open Browser URL",
    description: "Open a URL in controlled Action Chrome by default, or hand it off to the user's regular Chrome with mode=regular. Regular Chrome is visible and intentionally unavailable to Action Browser inspection, clicks, fills, and screenshots.",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to open. https:// is added when no scheme is provided." },
        mode: {
          type: "string",
          enum: ["action", "regular"],
          description: "Use controlled Action Chrome (default) or open-only regular Chrome. Regular mode never attaches automation to the personal profile.",
        },
        profile: {
          type: "string",
          description: "Optional Action profile name to use for this session (e.g. coding, mira). Only valid in action mode.",
        },
        background: { type: "boolean", description: "Action mode only: keep Chrome hidden in the background. Defaults to true. Regular mode is always visible." },
        waitMs: { type: "number", description: "Action mode only: maximum time to wait for the page to become ready. Defaults to 15000." },
        newTab: { type: "boolean", description: "Action mode only: create a separate tab instead of reusing this session's current tab. Defaults to false." },
      },
      required: ["url"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, idempotentHint: false },
  },
  {
    name: "browser_tabs",
    title: "List Action Browser Tabs",
    description: "List open page tabs in the active Action Chrome profile.",
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

async function useProfile(nextName: string): Promise<{
  profile: string;
  profileDir: string;
  switched: boolean;
  closedPrevious: boolean;
}> {
  if (fixedProfileDir) {
    throw new Error(
      "ACTION_BROWSER_PROFILE_DIR is fixed for this MCP process; unset it to switch named profiles.",
    );
  }
  const name = sanitizeProfileName(nextName);
  const nextDir = join(profileRoot, name);
  if (name === profileName && nextDir === profileDir) {
    writeProfileMeta(profileName, profileDir);
    return { profile: profileName, profileDir, switched: false, closedPrevious: false };
  }
  let closedPrevious = false;
  if (ownsBrowser) {
    const outcome = await releaseBrowser("profile-switch");
    closedPrevious = outcome.closed;
    currentTargetId = undefined;
  }
  profileName = name;
  profileDir = nextDir;
  writeProfileMeta(profileName, profileDir);
  return { profile: profileName, profileDir, switched: true, closedPrevious };
}

async function companionStatus(): Promise<JsonObject> {
  const dist = companionDistDir();
  const distExists = existsSync(dist);
  const manifestPath = join(dist, "manifest.json");
  let bridge: JsonObject = { ok: false, connected: false };
  try {
    const response = await fetch(companionBridgeHealthURL);
    bridge = await response.json() as JsonObject;
  } catch (error) {
    bridge = {
      ok: false,
      connected: false,
      error: error instanceof Error ? error.message : String(error),
      hint: "Start the bridge with: bun run chrome:companion:bridge",
    };
  }

  let extensionTargets: Array<{ type: string; title: string; url: string }> = [];
  let extensionIds: string[] = [];
  if (await chromeIsReady()) {
    try {
      const targets = await fetchJson<ChromeTarget[]>("/json/list");
      extensionTargets = targets
        .filter((target) => typeof target.url === "string" && target.url.includes("chrome-extension://"))
        .map((target) => ({ type: target.type, title: target.title, url: target.url }));
      extensionIds = [
        ...new Set(
          extensionTargets
            .map((target) => target.url.match(/^chrome-extension:\/\/([^/]+)\//)?.[1])
            .filter((id): id is string => Boolean(id)),
        ),
      ];
    } catch {
      // Chrome may not expose targets yet.
    }
  }

  return {
    profile: profileName,
    profileDir,
    companionDist: dist,
    companionDistExists: distExists,
    companionManifestExists: existsSync(manifestPath),
    bridgeHealthUrl: companionBridgeHealthURL,
    bridge,
    extensionTargets,
    extensionIds,
    setupHint: distExists
      ? `Load unpacked extension once in this Action profile: ${dist}`
      : "Build companion first: bun run chrome:companion:build",
  };
}

async function ensureChrome(background = true): Promise<void> {
  if (await chromeIsReady()) {
    claimBrowser();
    return;
  }

  await mkdir(profileDir, { recursive: true });
  writeProfileMeta(profileName, profileDir);
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

type PageReadiness = {
  readyState?: string;
  documentUrl?: string;
  title?: string;
  loaderId?: string;
  timedOut: boolean;
};

async function waitUntilReady(
  session: CDPSession,
  timeoutMs: number,
  expectedLoaderId?: string,
): Promise<PageReadiness> {
  const started = Date.now();
  let last: PageReadiness = { timedOut: true };
  while (true) {
    try {
      const frameTreeResult = await session.call("Page.getFrameTree");
      const result = await session.call("Runtime.evaluate", {
        expression: "({ readyState: document.readyState, documentUrl: location.href, title: document.title })",
        returnByValue: true,
      });
      const value = (result.result as JsonObject | undefined)?.value as JsonObject | undefined;
      const frameTree = frameTreeResult.frameTree as JsonObject | undefined;
      const frame = frameTree?.frame as JsonObject | undefined;
      last = {
        readyState: typeof value?.readyState === "string" ? value.readyState : undefined,
        documentUrl: typeof value?.documentUrl === "string" ? value.documentUrl : undefined,
        title: typeof value?.title === "string" ? value.title : undefined,
        loaderId: typeof frame?.loaderId === "string" ? frame.loaderId : undefined,
        timedOut: true,
      };
      if (navigationIsReady({
        ...last,
        expectedLoaderId,
        observedLoaderId: last.loaderId,
      })) return { ...last, timedOut: false };
    } catch {
      // Navigation may replace the execution context between polls.
    }
    if (Date.now() - started >= timeoutMs) return last;
    await Bun.sleep(Math.min(150, Math.max(1, timeoutMs - (Date.now() - started))));
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

function errorResult(data: JsonObject): ToolResult {
  return {
    isError: true,
    content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    structuredContent: data,
  };
}

async function callTool(name: string, args: JsonObject): Promise<ToolResult> {
  switch (name) {
    case "browser_profiles":
      return textResult({
        ok: true,
        profileRoot,
        current: { profile: profileName, profileDir, fixedProfileDir: Boolean(fixedProfileDir) },
        profiles: listActionProfilesOnDisk(),
        policy: {
          default: "Action-owned named profiles under ChromeProfiles",
          dailyChrome: "explicit opt-in only; not supported by browser_use_profile",
          cookies: "seed with browser_import_cookies using domain allowlists",
          companion: "load packages/chrome-companion/dist unpacked once per profile",
        },
      });

    case "browser_use_profile": {
      const result = await useProfile(asString(args.profile, "profile"));
      return textResult({ ok: true, ...result });
    }

    case "browser_profile_info": {
      const defaultDir = existsSync(join(profileDir, "Cookies"))
        ? profileDir
        : join(profileDir, "Default");
      return textResult({
        ok: true,
        profile: profileName,
        profileDir,
        defaultDir,
        hasCookiesDb: existsSync(join(defaultDir, "Cookies")),
        debugPort,
        fixedProfileDir: Boolean(fixedProfileDir),
        companion: await companionStatus(),
      });
    }

    case "browser_companion_status":
      return textResult({ ok: true, ...(await companionStatus()) });

    case "browser_import_cookies": {
      const cookies = await loadCookieModule();
      if (args.listSourceProfiles === true) {
        return textResult({
          ok: true,
          sourceProfiles: cookies.listPersonalProfiles(),
          actionProfiles: listActionProfilesOnDisk(),
        });
      }
      const domains = Array.isArray(args.domains)
        ? args.domains.map((entry) => String(entry).trim()).filter(Boolean)
        : [];
      const only = Array.isArray(args.only)
        ? args.only.map((entry) => String(entry).trim()).filter(Boolean)
        : [];
      const selectors = cookies.parseCookieSelectors(only);
      if (!domains.length && !selectors.length) {
        throw new Error("browser_import_cookies requires domains and/or only.");
      }
      const into = typeof args.into === "string" && args.into.trim()
        ? sanitizeProfileName(args.into)
        : profileName;
      const source = typeof args.source === "string" && args.source.trim()
        ? args.source.trim()
        : undefined;
      const sourceProfilePath = cookies.resolveSourceProfileDir(source);
      const matches = cookies.listCookieEntries(sourceProfilePath, { domains, selectors });
      if (args.confirm !== true) {
        return textResult({
          ok: true,
          dryRun: true,
          into,
          sourceProfilePath,
          count: matches.length,
          cookies: matches.map((cookie) => `${cookie.hostKey}:${cookie.name}`),
          confirmRequired: true,
          hint: "Re-call with confirm=true to write these cookies into the Action profile.",
        });
      }
      if (into === profileName && ownsBrowser) {
        await releaseBrowser("cookie-import");
        currentTargetId = undefined;
      }
      const result = cookies.importCookiesToActionProfile({
        into,
        sourceProfile: source,
        domains,
        selectors,
      });
      return textResult({ ok: true, dryRun: false, ...result });
    }

    case "browser_open": {
      const inputUrl = asString(args.url, "url");
      const url = normalizeURL(inputUrl);
      const mode = browserOpenMode(args.mode);
      if (mode === "regular") {
        if (typeof args.profile === "string" && args.profile.trim()) {
          throw new Error("profile is only available in action mode; regular mode uses the user's normal Chrome profile.");
        }
        const launch = Bun.spawn(regularChromeLaunchArgs(chromeAppName, url), {
          stdout: "ignore",
          stderr: "pipe",
        });
        const status = await launch.exited;
        if (status !== 0) {
          const stderr = await new Response(launch.stderr).text();
          throw new Error(stderr.trim() || `Could not open ${chromeAppName}.`);
        }
        return textResult({
          ok: true,
          mode,
          ...(inputUrl === url ? {} : { inputUrl }),
          openedUrl: url,
          controlAvailable: false,
          handoff: true,
          chrome: {
            app: chromeAppName,
            profile: "system-selected",
            profileVerified: false,
            automated: false,
          },
          message: "Opened in regular Chrome. Action Browser cannot inspect, click, fill, or screenshot this personal-profile tab.",
        });
      }
      if (typeof args.profile === "string" && args.profile.trim()) {
        await useProfile(args.profile);
      }
      const background = args.background !== false;
      const timeoutMs = Math.max(0, optionalNumber(args.waitMs, 15_000));
      await ensureChrome(background);
      let target: ChromeTarget | undefined;
      let reusedTab = false;
      if (shouldReuseCurrentTab({
        currentTargetId,
        newTab: args.newTab === true,
      })) {
        target = (await listTargets()).find((candidate) => candidate.id === currentTargetId);
        reusedTab = Boolean(target);
      }
      if (!target) {
        target = await fetchJson<ChromeTarget>("/json/new?about%3Ablank", { method: "PUT" });
        if (!target.webSocketDebuggerUrl) {
          throw new Error("Chrome created a tab without a DevTools endpoint.");
        }
      }
      currentTargetId = target.id;
      const session = await CDPSession.connect(target.webSocketDebuggerUrl);
      try {
        await session.call("Page.enable");
        const navigation = await session.call("Page.navigate", { url });
        const navigateErrorText = typeof navigation.errorText === "string"
          ? navigation.errorText
          : undefined;
        const loaderId = typeof navigation.loaderId === "string" ? navigation.loaderId : undefined;
        const readiness = await waitUntilReady(
          session,
          navigateErrorText ? Math.min(timeoutMs, 1_500) : timeoutMs,
          loaderId,
        );
        let page: JsonObject = {};
        try {
          page = await evaluateValue(
            session,
            "({ title: document.title, documentUrl: location.href, readyState: document.readyState, pageText: (document.body?.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 1000) })",
          ) as JsonObject;
        } catch {
          // The target metadata and readiness observation still provide a useful failure contract.
        }
        let observedTarget: ChromeTarget | undefined;
        try {
          observedTarget = (await fetchJson<ChromeTarget[]>("/json/list"))
            .find((candidate) => candidate.id === target.id);
        } catch {
          // Chrome can briefly withhold target metadata while replacing an error document.
        }
        const outcome = assessNavigation({
          requestedUrl: url,
          documentUrl: typeof page.documentUrl === "string"
            ? page.documentUrl
            : readiness.documentUrl,
          targetUrl: observedTarget?.url ?? target.url,
          title: typeof page.title === "string" ? page.title : readiness.title,
          readyState: typeof page.readyState === "string" ? page.readyState : readiness.readyState,
          timedOut: readiness.timedOut,
          timeoutMs,
          navigateErrorText,
          pageText: typeof page.pageText === "string" ? page.pageText : undefined,
        });
        const result: JsonObject = {
          ...outcome,
          mode,
          ...(inputUrl === url ? {} : { inputUrl }),
          reusedTab,
          tab: {
            id: target.id,
            title: page.title ?? readiness.title ?? observedTarget?.title ?? target.title,
            url: outcome.finalUrl,
          },
          chrome: {
            profile: profileName,
            profileDir,
            background,
            debugPort,
            session: sessionName,
          },
        };
        return outcome.ok ? textResult(result) : errorResult(result);
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
            instructions: "Action Browser uses named Action-owned Chrome profiles (not daily Chrome). Prefer browser_profiles / browser_use_profile for identity, browser_import_cookies with domain allowlists to seed logins, and browser_companion_status for the extension bridge. Fast path: browser_open → browser_screenshot.",
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
