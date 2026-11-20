import { UI_CONTROL_SYSTEM_PROMPT } from "@xecutioner/protocol";
import type { UiPlugin } from "@xecutioner/server";
import { type AnthropicTool, toAnthropicTools } from "./anthropic.js";
import {
  type AgentMessage,
  type AgentToolCall,
  type AgentToolDefinition,
  runWithTools,
  type ToolTraceEntry,
} from "./run-with-tools.js";

export type AnthropicAgentOptions = {
  apiKey: string;
  model: string;
  baseUrl?: string;
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
  fetch?: typeof fetch;
  defaultMaxSteps?: number;
  defaultWaitTimeoutMs?: number;
  toolTimeoutMs?: number;
};

export type AnthropicAgentRunInput = {
  goal: string;
  sessionId: string;
  maxSteps?: number;
  waitTimeoutMs?: number;
  onStep?: (step: { index: number; content?: string; toolCalls?: AgentToolCall[] }) => void;
  onToolCall?: (name: string, args: Record<string, unknown>, result: string) => void;
  signal?: AbortSignal;
};

export type AnthropicAgentRunResult = {
  answer: string;
  steps: number;
  sessionId: string;
  toolTrace: ToolTraceEntry[];
};

type AnthropicContentBlock =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
  | { type: "tool_result"; tool_use_id: string; content: string };

type AnthropicApiMessage = {
  role: "user" | "assistant";
  content: string | AnthropicContentBlock[];
};

function toAgentTools(tools: AnthropicTool[]): AgentToolDefinition[] {
  return tools.map((tool) => ({
    name: tool.name,
    description: tool.description,
    parameters: tool.input_schema,
  }));
}

function toAnthropicMessages(messages: AgentMessage[]): {
  system?: string;
  messages: AnthropicApiMessage[];
} {
  let system: string | undefined;
  const out: AnthropicApiMessage[] = [];

  for (const message of messages) {
    if (message.role === "system") {
      system = system ? `${system}\n\n${message.content}` : message.content;
      continue;
    }
    if (message.role === "user") {
      out.push({ role: "user", content: message.content });
      continue;
    }
    if (message.role === "assistant") {
      const blocks: AnthropicContentBlock[] = [];
      if (message.content) {
        blocks.push({ type: "text", text: message.content });
      }
      for (const call of message.toolCalls ?? []) {
        blocks.push({
          type: "tool_use",
          id: call.id,
          name: call.name,
          input: call.args,
        });
      }
      out.push({ role: "assistant", content: blocks.length ? blocks : "" });
      continue;
    }
    out.push({
      role: "user",
      content: [
        {
          type: "tool_result",
          tool_use_id: message.toolCallId,
          content: message.content,
        },
      ],
    });
  }

  return { system, messages: out };
}

async function anthropicComplete(options: {
  apiKey: string;
  model: string;
  baseUrl: string;
  fetchImpl: typeof fetch;
  system?: string;
  messages: AnthropicApiMessage[];
  tools: AnthropicTool[];
  temperature?: number;
  maxTokens: number;
  signal?: AbortSignal;
}): Promise<{ content?: string; toolCalls?: AgentToolCall[] }> {
  const url = `${options.baseUrl.replace(/\/$/, "")}/v1/messages`;
  const response = await options.fetchImpl(url, {
    method: "POST",
    headers: {
      "x-api-key": options.apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: options.model,
      max_tokens: options.maxTokens,
      system: options.system,
      messages: options.messages,
      tools: options.tools,
      temperature: options.temperature,
    }),
    signal: options.signal,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Anthropic HTTP ${response.status}: ${text}`);
  }

  const data = (await response.json()) as {
    content?: AnthropicContentBlock[];
  };

  const textParts: string[] = [];
  const toolCalls: AgentToolCall[] = [];
  for (const block of data.content ?? []) {
    if (block.type === "text") {
      textParts.push(block.text);
    } else if (block.type === "tool_use") {
      toolCalls.push({
        id: block.id,
        name: block.name,
        args: block.input ?? {},
      });
    }
  }

  return {
    content: textParts.join("\n").trim() || undefined,
    toolCalls: toolCalls.length ? toolCalls : undefined,
  };
}

/**
 * Anthropic Messages UI-control agent (fetch-based; no hard SDK dep).
 */
export function createAnthropicAgent(plugin: UiPlugin, options: AnthropicAgentOptions) {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  if (!fetchImpl) {
    throw new Error("fetch is not available; pass options.fetch");
  }
  const baseUrl = options.baseUrl ?? "https://api.anthropic.com";
  const systemPrompt = options.systemPrompt ?? UI_CONTROL_SYSTEM_PROMPT;

  return {
    async run(input: AnthropicAgentRunInput): Promise<AnthropicAgentRunResult> {
      await plugin.waitForClient(
        input.sessionId,
        input.waitTimeoutMs ?? options.defaultWaitTimeoutMs ?? 10_000,
      );

      const { tools, execute } = toAnthropicTools(plugin, input.sessionId, {
        timeoutMs: options.toolTimeoutMs,
      });

      const result = await runWithTools({
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: input.goal },
        ],
        tools: toAgentTools(tools),
        execute,
        maxSteps: input.maxSteps ?? options.defaultMaxSteps ?? 12,
        onStep: input.onStep,
        onToolCall: input.onToolCall,
        signal: input.signal,
        complete: async (messages) => {
          const mapped = toAnthropicMessages(messages);
          return anthropicComplete({
            apiKey: options.apiKey,
            model: options.model,
            baseUrl,
            fetchImpl,
            system: mapped.system,
            messages: mapped.messages,
            tools,
            temperature: options.temperature,
            maxTokens: options.maxTokens ?? 4096,
            signal: input.signal,
          });
        },
      });

      return {
        answer: result.answer,
        steps: result.steps,
        sessionId: input.sessionId,
        toolTrace: result.toolTrace,
      };
    },
  };
}
