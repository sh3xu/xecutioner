import {
  type Command,
  type CommandAction,
  type CommandResult,
  createCallId,
  createIdempotencyKey,
  DEFAULT_COMMAND_TIMEOUT_MS,
  formatAppContextForModel,
  formatSnapshotAsUntrusted,
  getToolDefinition,
  UI_TOOL_DEFINITIONS,
  type UiToolName,
} from "@xecutioner/protocol";
import type { UiPlugin } from "./plugin.js";

export type ToolInvokeArgs = Record<string, unknown>;

export type ToolInvokeResult = {
  content: string;
  result: CommandResult;
};

function actionFromTool(name: UiToolName): CommandAction {
  const def = getToolDefinition(name);
  if (!def) {
    throw new Error(`Unknown tool: ${name}`);
  }
  return def.action;
}

/**
 * Build a Command from a tool name and arguments.
 * Optional overrides for callId / idempotency / deadline.
 */
export function buildCommandFromToolArgs(
  name: UiToolName,
  args: ToolInvokeArgs,
  options?: {
    callId?: string;
    idempotencyKey?: string;
    timeoutMs?: number;
    now?: number;
  },
): Command {
  const now = options?.now ?? Date.now();
  const timeoutMs = options?.timeoutMs ?? DEFAULT_COMMAND_TIMEOUT_MS;
  const action = actionFromTool(name);

  const command: Command = {
    callId: options?.callId ?? createCallId(),
    action,
    idempotencyKey: options?.idempotencyKey ?? createIdempotencyKey(),
    deadline: now + timeoutMs,
  };

  if (typeof args.elementId === "string") {
    command.elementId = args.elementId;
  }
  if (typeof args.snapshotId === "string") {
    command.snapshotId = args.snapshotId;
  }
  if (typeof args.text === "string") {
    command.text = args.text;
  }
  if (
    args.direction === "up" ||
    args.direction === "down" ||
    args.direction === "left" ||
    args.direction === "right"
  ) {
    command.direction = args.direction;
  }
  if (typeof args.amount === "number") {
    command.amount = args.amount;
  }
  if (typeof args.screenId === "string") {
    command.screenId = args.screenId;
  }
  if (args.params && typeof args.params === "object" && !Array.isArray(args.params)) {
    command.params = args.params as Record<string, unknown>;
  }
  if (typeof args.maxDestinations === "number") {
    command.maxDestinations = args.maxDestinations;
  }
  if (action === "wait_for") {
    command.waitCondition = {
      elementId: typeof args.elementId === "string" ? args.elementId : undefined,
      labelContains: typeof args.labelContains === "string" ? args.labelContains : undefined,
      timeoutMs: typeof args.timeoutMs === "number" ? args.timeoutMs : undefined,
    };
  }

  return command;
}

export function formatToolResultForModel(result: CommandResult): string {
  if (!result.ok) {
    return JSON.stringify({
      ok: false,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      snapshotId: result.snapshot?.snapshotId,
      currentScreen: result.appContext?.current.screenId,
    });
  }

  const parts: string[] = [];
  if (result.appContext) {
    parts.push(formatAppContextForModel(result.appContext));
  }
  if (result.snapshot) {
    parts.push(formatSnapshotAsUntrusted(result.snapshot));
  }
  if (parts.length) {
    return parts.join("\n\n");
  }
  return JSON.stringify({ ok: true });
}

export function listToolDefinitions() {
  return UI_TOOL_DEFINITIONS;
}

/**
 * Invoke a UI tool against a plugin session and format the model-facing result.
 */
export async function invokeUiTool(
  plugin: UiPlugin,
  sessionId: string,
  name: UiToolName,
  args: ToolInvokeArgs,
  options?: { timeoutMs?: number },
): Promise<ToolInvokeResult> {
  const command = buildCommandFromToolArgs(name, args, {
    timeoutMs: options?.timeoutMs,
  });
  const result = await plugin.dispatch(sessionId, command);
  return {
    content: formatToolResultForModel(result),
    result,
  };
}
