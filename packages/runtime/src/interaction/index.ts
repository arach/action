import type { ResolvedTarget, RuntimeAction } from "@action/protocol";

interface CalculatorButtonDescriptor {
  text?: string;
  semanticId?: string;
}

type HostRunner = (command: string, ...args: string[]) => Promise<{ stdout: string }>;

export interface InteractionExecutionContext {
  runHost: HostRunner;
  resolveCalculatorButton: (query: CalculatorButtonDescriptor) => string;
  resolveBundleId: (surfaceId: string | undefined) => string | undefined;
}

function numberFromInput(input: unknown): number | undefined {
  if (typeof input === "number" && Number.isFinite(input)) {
    return input;
  }

  if (typeof input === "string") {
    const value = Number(input);
    if (Number.isFinite(value)) {
      return value;
    }
  }

  return undefined;
}

function pointFromInput(input: unknown): { x: number; y: number } | undefined {
  if (!input || typeof input !== "object") {
    return undefined;
  }

  const record = input as Record<string, unknown>;
  const x = numberFromInput(record.x);
  const y = numberFromInput(record.y);
  if (x === undefined || y === undefined) {
    return undefined;
  }

  return { x, y };
}

function centerOfBounds(input: unknown): { x: number; y: number } | undefined {
  if (!input || typeof input !== "object") {
    return undefined;
  }

  const record = input as Record<string, unknown>;
  const x = numberFromInput(record.x);
  const y = numberFromInput(record.y);
  const width = numberFromInput(record.width);
  const height = numberFromInput(record.height);

  if (x === undefined || y === undefined || width === undefined || height === undefined) {
    return undefined;
  }

  return {
    x: x + width / 2,
    y: y + height / 2,
  };
}

function stringArray(input: unknown): string[] {
  if (!Array.isArray(input)) {
    return [];
  }

  return input.filter((value): value is string => typeof value === "string" && value.length > 0);
}

function stringValue(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 ? input : undefined;
}

function numberValue(input: unknown): number | undefined {
  return typeof input === "number" && Number.isFinite(input) ? input : undefined;
}

function targetLabel(action: RuntimeAction, target: ResolvedTarget | undefined): string | undefined {
  return stringValue(action.input?.targetLabel)
    ?? stringValue(action.input?.label)
    ?? action.target?.text
    ?? action.target?.semanticId
    ?? target?.label;
}

function targetRole(action: RuntimeAction): string | undefined {
  return stringValue(action.input?.role) ?? action.target?.role;
}

function targetBundleId(
  action: RuntimeAction,
  target: ResolvedTarget | undefined,
  context: InteractionExecutionContext,
): string | undefined {
  return stringValue(action.input?.bundleId)
    ?? context.resolveBundleId(action.target?.surfaceId ?? target?.surfaceId);
}

export async function executeInteractionAction(
  action: RuntimeAction,
  target: ResolvedTarget | undefined,
  context: InteractionExecutionContext,
): Promise<void> {
  if (action.kind === "type") {
    const text = String(action.input?.text ?? "");
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label) {
      const args = [
        "set-accessibility-value",
        "--bundle-id", bundleId,
        "--label", label,
        "--value", text,
      ];
      const role = targetRole(action);
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    const delayMs = numberValue(action.input?.delayMs);
    const args = ["type-text", "--text", text];
    if (delayMs && delayMs > 0) {
      args.push("--delay-ms", String(Math.round(delayMs)));
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "press-key") {
    const keys = stringArray(action.input?.keys);
    const modifiers = stringArray(action.input?.modifiers);
    const key = stringValue(action.input?.key) ?? keys.at(-1) ?? "";
    const normalizedModifiers = keys.length > 1 ? keys.slice(0, -1) : modifiers;
    const args = ["press-key", "--key", key];
    if (normalizedModifiers.length > 0) {
      args.push("--modifiers", normalizedModifiers.join(","));
    }
    await context.runHost(args[0], ...args.slice(1));
    return;
  }

  if (action.kind === "click") {
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label) {
      const args = [
        "press-accessibility-element",
        "--bundle-id", bundleId,
        "--label", label,
      ];
      const role = targetRole(action);
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    const point = action.target?.point;
    if (point) {
      await context.runHost(
        "click-point",
        "--x",
        String(point.x),
        "--y",
        String(point.y),
      );
      return;
    }

    const buttonLabel = context.resolveCalculatorButton(
      target ? { text: target.label, semanticId: target.id } : action.target ?? {},
    );
    await context.runHost("click-calculator-button", "--button", buttonLabel);
    return;
  }

  if (action.kind === "drag") {
    const fromFromCoordinates = (() => {
      const x = numberFromInput(action.input?.fromX);
      const y = numberFromInput(action.input?.fromY);

      if (x === undefined || y === undefined) {
        return undefined;
      }

      return { x, y };
    })();

    const sourcePoint = pointFromInput(action.input?.from)
      ?? pointFromInput(action.input?.source)
      ?? pointFromInput(action.input?.start)
      ?? fromFromCoordinates;

    const toFromCoordinates = (() => {
      const x = numberFromInput(action.input?.toX);
      const y = numberFromInput(action.input?.toY);

      if (x === undefined || y === undefined) {
        return undefined;
      }

      return { x, y };
    })();

    const targetPoint = pointFromInput(action.input?.to)
      || pointFromInput(action.input?.destination)
      || pointFromInput(action.input?.targetPoint)
      || pointFromInput(action.input?.end)
      || toFromCoordinates
      || centerOfBounds(target?.bounds)
      || centerOfBounds(action.target);

    if (!sourcePoint || !targetPoint) {
      throw new Error("Drag action requires both from and to points");
    }

    const durationMs = numberFromInput(action.input?.durationMs) ?? numberValue(action.input?.duration) ?? 0;
    const filePath = stringValue(action.input?.filePath);

    const args = [
      "drag",
      "--from-x", String(sourcePoint.x),
      "--from-y", String(sourcePoint.y),
      "--to-x", String(targetPoint.x),
      "--to-y", String(targetPoint.y),
    ];
    if (durationMs > 0) {
      args.push("--duration-ms", String(Math.round(durationMs)));
    }
    if (filePath) {
      args.push("--file-path", filePath);
    }

    await context.runHost(args[0], ...args.slice(1));
  }
}
