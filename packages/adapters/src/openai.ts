import type { UiPlugin } from "@xecutioner/server";
import { bindUiToolHandlers, listDefinitions } from "./common.js";

export {
  createOpenAiAgent,
  type OpenAiAgentOptions,
  type OpenAiAgentRunInput,
  type OpenAiAgentRunResult,
} from "./openai-agent.js";

export type OpenAiTool = {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
};

export type OpenAiToolsBundle = {
  tools: OpenAiTool[];
  execute: (name: string, args: Record<string, unknown>) => Promise<string>;
};

/**
 * Export UI tools for OpenAI Chat Completions / Responses tool calling.
 */
export function toOpenAiTools(
  plugin: UiPlugin,
  sessionId: string,
  options?: { timeoutMs?: number },
): OpenAiToolsBundle {
  const handlers = bindUiToolHandlers(plugin, sessionId, options);
  const tools: OpenAiTool[] = listDefinitions().map((def) => ({
    type: "function",
    function: {
      name: def.name,
      description: def.description,
      parameters: def.parameters as unknown as Record<string, unknown>,
    },
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
