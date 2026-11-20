import type { UiPlugin } from "@xecutioner/server";
import { bindUiToolHandlers, listDefinitions } from "./common.js";

export type VercelAiTool = {
  description: string;
  parameters: Record<string, unknown>;
  execute: (args: Record<string, unknown>) => Promise<string>;
};

/**
 * Export UI tools in a Vercel AI SDK-compatible shape.
 */
export function toVercelAiTools(
  plugin: UiPlugin,
  sessionId: string,
  options?: { timeoutMs?: number },
): Record<string, VercelAiTool> {
  const handlers = bindUiToolHandlers(plugin, sessionId, options);
  const tools: Record<string, VercelAiTool> = {};

  for (const def of listDefinitions()) {
    tools[def.name] = {
      description: def.description,
      parameters: def.parameters as unknown as Record<string, unknown>,
      execute: (args) => handlers[def.name](args),
    };
  }

  return tools;
}

/**
 * Ready-to-pass UI tools for generateText / streamText.
 */
export function createVercelAiUiTools(
  plugin: UiPlugin,
  sessionId: string,
  options?: { timeoutMs?: number },
): Record<string, VercelAiTool> {
  return toVercelAiTools(plugin, sessionId, options);
}
