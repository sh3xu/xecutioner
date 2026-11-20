import type { UiToolName } from "@xecutioner/protocol";
import type { ToolInvokeArgs, UiPlugin } from "@xecutioner/server";

export type ScriptedStep = {
  tool: UiToolName;
  args: ToolInvokeArgs;
};

export type EvalStepResult = {
  tool: UiToolName;
  ok: boolean;
  content: string;
  latencyMs: number;
};

/**
 * Scripted agent that invokes UI tools in order — no model required.
 */
export async function runScriptedAgent(
  plugin: UiPlugin,
  sessionId: string,
  steps: ScriptedStep[],
): Promise<EvalStepResult[]> {
  const results: EvalStepResult[] = [];
  for (const step of steps) {
    const started = Date.now();
    const { content, result } = await plugin.invokeTool(sessionId, step.tool, step.args);
    results.push({
      tool: step.tool,
      ok: result.ok,
      content,
      latencyMs: Date.now() - started,
    });
    if (!result.ok) {
      break;
    }
  }
  return results;
}
