#!/usr/bin/env bun

import { compileScenario } from "@action/compiler";
import {
  exportSessionAssets,
  inspectCurrentSurface,
  runScenarioSource,
  settleCurrentSurfaceViewport,
  verifyMediaAsset,
  type SourceRunDriver,
} from "@action/runtime";

import { runScenarioGuidedCaptureDemo } from "./index.js";
import { loadScenario } from "./scenarios.js";
import type { CaptureProfile } from "@action/protocol";
import type { DemoEngineMode } from "./index.js";

const runtime = globalThis as typeof globalThis & {
  process: {
    argv: string[];
    stdout: {
      write(text: string): void;
    };
  };
};

function printJson(value: unknown): void {
  runtime.process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function parseFlags(args: string[]): {
  positionals: string[];
  flags: Record<string, string>;
} {
  const positionals: string[] = [];
  const flags: Record<string, string> = {};

  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (!value.startsWith("--")) {
      positionals.push(value);
      continue;
    }

    const name = value.slice(2);
    const next = args[index + 1];
    if (!next || next.startsWith("--")) {
      flags[name] = "true";
      continue;
    }

    flags[name] = next;
    index += 1;
  }

  return { positionals, flags };
}

function requiredNumber(flags: Record<string, string>, key: string): number {
  const raw = flags[key];
  const value = raw === undefined ? Number.NaN : Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`Missing or invalid --${key}`);
  }
  return value;
}

function optionalCaptureProfile(flags: Record<string, string>): CaptureProfile | undefined {
  const profile = flags.profile;
  if (profile === undefined) {
    return undefined;
  }

  if (profile === "draft" || profile === "final") {
    return profile;
  }

  throw new Error("--profile must be draft or final");
}

function optionalEngineMode(input: string | undefined): DemoEngineMode | undefined {
  if (input === undefined) {
    return undefined;
  }

  if (input === "mock" || input === "macos") {
    return input;
  }

  throw new Error("driver must be mock or macos");
}

function optionalSourceRunDriver(input: string | undefined): SourceRunDriver | undefined {
  if (input === undefined) {
    return undefined;
  }

  if (input === "mock" || input === "macos" || input === "browser") {
    return input;
  }

  throw new Error("driver must be mock, macos, or browser");
}

async function main(argv: string[]): Promise<void> {
  const [command, ...rest] = argv;
  const { positionals, flags } = parseFlags(rest);
  const [arg, extra] = positionals;

  if (command === "source") {
    const [subcommand, scenarioId, driverArg] = positionals;
    if (subcommand !== "run" || !scenarioId) {
      throw new Error("Usage: action source run <scenario-id> [mock|macos|browser] [--export] [--to <dir>] [--profile draft|final] [--url <browser-url>]");
    }

    const driver = optionalSourceRunDriver(flags.driver ?? driverArg) ?? "mock";
    const profile = optionalCaptureProfile(flags) ?? (driver === "mock" ? "draft" : "final");
    const result = await runScenarioSource({
      scenario: await loadScenario(scenarioId),
      driver,
      captureProfile: profile,
      exportAssets: flags.export === "true",
      outputDir: flags.to,
      browserUrl: flags.url ?? flags["browser-url"],
      browserSession: flags["browser-session"],
    });
    printJson(result);
    return;
  }

  if (command === "demo" && arg) {
    const scenario = await loadScenario(arg);
    const result = await runScenarioGuidedCaptureDemo(
      scenario,
      extra === "macos" ? "macos" : "mock",
      { captureProfile: optionalCaptureProfile(flags) },
    );
    printJson(result);
    return;
  }

  if (command === "calculator-demo") {
    const scenario = await loadScenario("calculator-demo");
    const result = await runScenarioGuidedCaptureDemo(
      scenario,
      arg === "macos" ? "macos" : "mock",
      { captureProfile: optionalCaptureProfile(flags) },
    );
    printJson(result);
    return;
  }

  if (command === "scenario" && arg) {
    const scenario = await loadScenario(arg);
    printJson(compileScenario(scenario));
    return;
  }

  if (command === "inspect" && arg === "current-surface") {
    const result = await inspectCurrentSurface();
    printJson(result);
    return;
  }

  if (command === "settle" && arg === "current-surface") {
    const result = await settleCurrentSurfaceViewport({
      targetViewport: {
        x: requiredNumber(flags, "x"),
        y: requiredNumber(flags, "y"),
        width: requiredNumber(flags, "width"),
        height: requiredNumber(flags, "height"),
      },
      providerId: flags.provider === "mock" ? "mock" : "pie-minimax",
      maxTurns: flags["max-turns"] ? requiredNumber(flags, "max-turns") : undefined,
    });
    printJson(result);
    return;
  }

  if (command === "export" && arg) {
    const result = await exportSessionAssets({
      sessionIdOrPath: arg,
      outputDir: flags.to,
    });
    printJson(result);
    return;
  }

  if (command === "verify" && arg) {
    const result = await verifyMediaAsset({
      path: arg,
      minDurationSeconds: flags["min-duration"] ? requiredNumber(flags, "min-duration") : undefined,
      minFrameCount: flags["min-frames"] ? requiredNumber(flags, "min-frames") : undefined,
      minWidth: flags["min-width"] ? requiredNumber(flags, "min-width") : undefined,
      minHeight: flags["min-height"] ? requiredNumber(flags, "min-height") : undefined,
    });
    printJson(result);
    return;
  }

  printJson({
    commands: [
      "bun packages/cli/src/main.ts source run <scenario-id> [mock|macos|browser] [--export] [--to <output-dir>] [--profile final|draft] [--url <browser-url>]",
      "bun packages/cli/src/main.ts inspect current-surface",
      "bun packages/cli/src/main.ts settle current-surface --x <x> --y <y> --width <w> --height <h> [--provider mock|pie-minimax]",
      "bun packages/cli/src/main.ts export <session-id-or-path> [--to <output-dir>]",
      "bun packages/cli/src/main.ts verify <video-path> [--min-duration <seconds>] [--min-frames <count>]",
      "bun packages/cli/src/main.ts demo <scenario-id> macos [--profile final|draft]",
      "bun run demo:calculator",
      "bun run demo:notes",
      "bun run demo:calculator:macos",
      "bun run demo:notes:macos",
      "bun run scenario:calculator",
      "bun run scenario:notes",
      "bun packages/cli/src/main.ts demo <scenario-id> [mock|macos]",
      "bun packages/cli/src/main.ts scenario <scenario-id>",
    ],
  });
}

function cliArgs(argv: string[]): string[] {
  const maybeScript = argv[1];

  if (maybeScript && (maybeScript.endsWith(".ts") || maybeScript.endsWith(".js") || maybeScript.includes("/"))) {
    return argv.slice(2);
  }

  return argv.slice(1);
}

void main(cliArgs(runtime.process.argv));
