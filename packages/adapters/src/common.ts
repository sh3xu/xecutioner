import { UI_TOOL_DEFINITIONS, type UiToolDefinition, type UiToolName } from "@xecutioner/protocol";
import type { ToolInvokeArgs, UiPlugin } from "@xecutioner/server";

export type BoundToolHandler = (args: ToolInvokeArgs) => Promise<string>;

export type BoundUiTools = Record<UiToolName, BoundToolHandler>;

/**
 * Bind all UI tools to a plugin session. Shared by every adapter.
 */
export function bindUiToolHandlers(
  plugin: UiPlugin,
  sessionId: string,
  options?: { timeoutMs?: number },
): BoundUiTools {
  const handlers = {} as BoundUiTools;
  for (const def of UI_TOOL_DEFINITIONS) {
    handlers[def.name] = async (args) => {
      const { content } = await plugin.invokeTool(sessionId, def.name, args, options);
      return content;
    };
  }
  return handlers;
}

export function listDefinitions(): UiToolDefinition[] {
  return UI_TOOL_DEFINITIONS;
}
