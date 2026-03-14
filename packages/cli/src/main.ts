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

  if (command === "calculator-demo") {
    const scenario = await loadScenario("calculator-demo");
    const result = await runScenarioGuidedCaptureDemo(
      scenario,
      arg === "macos" ? "macos" : "mock",
    );
    printJson(result);
    return;
  }

  if (command === "scenario" && arg === "calculator-demo") {
    const scenario = await loadScenario("calculator-demo");
    printJson(compileScenario(scenario));
    return;
  }

  printJson({
    commands: [
      "bun run demo:calculator",
      "bun run demo:calculator:macos",
      "bun run scenario:calculator",
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
