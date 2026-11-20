import type { UiPlugin } from "@xecutioner/server";
import { bindUiToolHandlers, listDefinitions } from "./common.js";

export {
  type AnthropicAgentOptions,
  type AnthropicAgentRunInput,
  type AnthropicAgentRunResult,
  createAnthropicAgent,
} from "./anthropic-agent.js";

export type AnthropicTool = {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
};

export type AnthropicToolsBundle = {
  tools: AnthropicTool[];
  execute: (name: string, args: Record<string, unknown>) => Promise<string>;
};

/**
 * Export UI tools for Anthropic Messages tool use.
 */
export function toAnthropicTools(
  plugin: UiPlugin,
  sessionId: string,
  options?: { timeoutMs?: number },
): AnthropicToolsBundle {
  const handlers = bindUiToolHandlers(plugin, sessionId, options);
  const tools: AnthropicTool[] = listDefinitions().map((def) => ({
    name: def.name,
    description: def.description,
    input_schema: def.parameters as unknown as Record<string, unknown>,
  }));

  return {
    tools,
    execute: async (name, args) => {
      const handler = handlers[name as keyof typeof handlers];
      if (!handler) {
        throw new Error(`Unknown UI tool: ${name}`);
      }
      return handler(args);
    },
  };
}
