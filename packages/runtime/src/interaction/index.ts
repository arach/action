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

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function targetLabel(action: RuntimeAction, target: ResolvedTarget | undefined): string | undefined {
  return stringValue(action.input?.targetLabel)
    ?? stringValue(action.input?.label)
    ?? target?.label
    ?? action.target?.text
    ?? action.target?.semanticId;
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
  if (action.kind === "wait-for-condition") {
    const durationMs = numberValue(action.input?.durationMs)
      ?? numberValue(action.input?.timeoutMs)
      ?? numberValue(action.input?.ms)
      ?? 800;
    await sleep(Math.max(0, durationMs));
    return;
  }

  if (action.kind === "show-cue") {
    return;
  }

  if (action.kind === "type") {
    const text = String(action.input?.text ?? "");
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    const role = targetRole(action);
    if (bundleId && role && !label) {
      await context.runHost(
        "set-accessibility-role-value",
        "--bundle-id",
        bundleId,
        "--role",
        role,
        "--value",
        text,
      );
      return;
    }
    if (bundleId && label) {
      const args = [
        "set-accessibility-value",
        "--bundle-id", bundleId,
        "--label", label,
        "--value", text,
      ];
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

  if (action.kind === "set-value") {
    const rawValue = action.input?.value ?? action.input?.text;
    const value = rawValue === undefined ? "" : String(rawValue);
    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    const role = targetRole(action);
    if (!bundleId) {
      throw new Error("Set-value action requires a target app surface");
    }

    if (label) {
      const args = [
        "set-accessibility-value",
        "--bundle-id", bundleId,
        "--label", label,
        "--value", value,
      ];
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
      return;
    }

    if (!role) {
      throw new Error("Set-value action requires a label or role");
    }

    await context.runHost(
      "set-accessibility-role-value",
      "--bundle-id",
      bundleId,
      "--role",
      role,
      "--value",
      value,
    );
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

    const bundleId = targetBundleId(action, target, context);
    const label = targetLabel(action, target);
    if (bundleId && label) {
      const accessibilityAction = stringValue(action.input?.axAction)
        ?? stringValue(action.input?.accessibilityAction);
      const args = [
        accessibilityAction ? "perform-accessibility-action" : "press-accessibility-element",
        "--bundle-id", bundleId,
        "--label", label,
      ];
      if (accessibilityAction) {
        args.push("--action", accessibilityAction);
      }
      const role = targetRole(action);
      if (role) {
        args.push("--role", role);
      }
      await context.runHost(args[0], ...args.slice(1));
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
