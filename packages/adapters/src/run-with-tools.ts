export type AgentMessage =
  | { role: "system"; content: string }
  | { role: "user"; content: string }
  | { role: "assistant"; content?: string; toolCalls?: AgentToolCall[] }
  | { role: "tool"; toolCallId: string; name: string; content: string };

export type AgentToolCall = {
  id: string;
  name: string;
  args: Record<string, unknown>;
};

export type AgentCompleteResult = {
  content?: string;
  toolCalls?: AgentToolCall[];
};

export type AgentToolDefinition = {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
};

export type ToolTraceEntry = {
  name: string;
  args: Record<string, unknown>;
  result: string;
};

export type RunWithToolsOptions = {
  messages: AgentMessage[];
  tools: AgentToolDefinition[];
  execute: (name: string, args: Record<string, unknown>) => Promise<string>;
  complete: (
    messages: AgentMessage[],
    tools: AgentToolDefinition[],
  ) => Promise<AgentCompleteResult>;
  maxSteps?: number;
  onStep?: (step: { index: number; content?: string; toolCalls?: AgentToolCall[] }) => void;
  onToolCall?: (name: string, args: Record<string, unknown>, result: string) => void;
  signal?: AbortSignal;
};

export type RunWithToolsResult = {
  answer: string;
  steps: number;
  messages: AgentMessage[];
  toolTrace: ToolTraceEntry[];
};

function assertNotAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw new Error("Aborted");
  }
}

/**
 * Provider-agnostic tool-call loop for UI control agents.
 */
export async function runWithTools(options: RunWithToolsOptions): Promise<RunWithToolsResult> {
  const maxSteps = options.maxSteps ?? 12;
  const messages = [...options.messages];
  const toolTrace: ToolTraceEntry[] = [];
  let steps = 0;
  let answer = "";

  for (let index = 0; index < maxSteps; index += 1) {
    assertNotAborted(options.signal);
    const completion = await options.complete(messages, options.tools);
    steps += 1;
    options.onStep?.({
      index,
      content: completion.content,
      toolCalls: completion.toolCalls,
    });

    const toolCalls = completion.toolCalls ?? [];
    messages.push({
      role: "assistant",
      content: completion.content,
      toolCalls: toolCalls.length ? toolCalls : undefined,
    });

    if (!toolCalls.length) {
      answer = completion.content?.trim() ?? "";
      break;
    }

    for (const call of toolCalls) {
      assertNotAborted(options.signal);
      const result = await options.execute(call.name, call.args);
      toolTrace.push({ name: call.name, args: call.args, result });
      options.onToolCall?.(call.name, call.args, result);
      messages.push({
        role: "tool",
        toolCallId: call.id,
        name: call.name,
        content: result,
      });
    }
  }

  if (!answer) {
    const lastAssistant = [...messages].reverse().find((m) => m.role === "assistant");
    answer = lastAssistant && "content" in lastAssistant ? (lastAssistant.content ?? "") : "";
  }

  return { answer, steps, messages, toolTrace };
}
