#!/usr/bin/env bun

import { compileScenario } from "@action/compiler";

import { runScenarioGuidedCaptureDemo } from "./index.js";
import { loadScenario } from "./scenarios.js";

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

async function main(argv: string[]): Promise<void> {
  const [command, arg, extra] = argv;

  if (command === "demo" && arg) {
    const scenario = await loadScenario(arg);
    const result = await runScenarioGuidedCaptureDemo(
      scenario,
      extra === "macos" ? "macos" : "mock",
    );
    printJson(result);
    return;
  }

  if (command === "calculator-demo") {
    const scenario = await loadScenario("calculator-demo");
    const result = await runScenarioGuidedCaptureDemo(
      scenario,
      arg === "macos" ? "macos" : "mock",
    );
    printJson(result);
    return;
  }

  if (command === "scenario" && arg) {
    const scenario = await loadScenario(arg);
    printJson(compileScenario(scenario));
    return;
  }

  printJson({
    commands: [
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
