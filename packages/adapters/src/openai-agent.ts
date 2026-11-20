import { UI_CONTROL_SYSTEM_PROMPT } from "@xecutioner/protocol";
import type { UiPlugin } from "@xecutioner/server";
import { type OpenAiTool, toOpenAiTools } from "./openai.js";
import {
  type AgentMessage,
  type AgentToolCall,
  type AgentToolDefinition,
  runWithTools,
  type ToolTraceEntry,
} from "./run-with-tools.js";

export type OpenAiAgentOptions = {
  apiKey: string;
  model: string;
  baseUrl?: string;
  systemPrompt?: string;
  temperature?: number;
  fetch?: typeof fetch;
  defaultMaxSteps?: number;
  defaultWaitTimeoutMs?: number;
  toolTimeoutMs?: number;
};

export type OpenAiAgentRunInput = {
  goal: string;
  sessionId: string;
  maxSteps?: number;
  waitTimeoutMs?: number;
  onStep?: (step: { index: number; content?: string; toolCalls?: AgentToolCall[] }) => void;
  onToolCall?: (name: string, args: Record<string, unknown>, result: string) => void;
  signal?: AbortSignal;
};

export type OpenAiAgentRunResult = {
  answer: string;
  steps: number;
  sessionId: string;
  toolTrace: ToolTraceEntry[];
};

type OpenAiChatMessage =
  | {
      role: "system" | "user" | "assistant";
      content: string | null;
      tool_calls?: OpenAiApiToolCall[];
    }
  | { role: "tool"; tool_call_id: string; content: string };

type OpenAiApiToolCall = {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
};

function toAgentTools(tools: OpenAiTool[]): AgentToolDefinition[] {
  return tools.map((tool) => ({
    name: tool.function.name,
    description: tool.function.description,
    parameters: tool.function.parameters,
  }));
}

function toOpenAiMessages(messages: AgentMessage[]): OpenAiChatMessage[] {
  const out: OpenAiChatMessage[] = [];
  for (const message of messages) {
    if (message.role === "system" || message.role === "user") {
      out.push({ role: message.role, content: message.content });
      continue;
    }
    if (message.role === "assistant") {
      out.push({
        role: "assistant",
        content: message.content ?? null,
        tool_calls: message.toolCalls?.map((call) => ({
          id: call.id,
          type: "function" as const,
          function: {
            name: call.name,
            arguments: JSON.stringify(call.args),
          },
        })),
      });
      continue;
    }
    out.push({
      role: "tool",
      tool_call_id: message.toolCallId,
      content: message.content,
    });
  }
  return out;
}

function parseArgs(raw: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // NOTE: model sometimes returns non-JSON; treat as empty args
  }
  return {};
}

async function openAiComplete(options: {
  apiKey: string;
  model: string;
  baseUrl: string;
  fetchImpl: typeof fetch;
  messages: OpenAiChatMessage[];
  tools: OpenAiTool[];
  temperature?: number;
  signal?: AbortSignal;
}): Promise<{ content?: string; toolCalls?: AgentToolCall[] }> {
  const url = `${options.baseUrl.replace(/\/$/, "")}/chat/completions`;

  const attempt = async (body: Record<string, unknown>) => {
    const response = await options.fetchImpl(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${options.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: options.signal,
    });
    if (!response.ok) {
      const text = await response.text();
      const error = new Error(`OpenAI HTTP ${response.status}: ${text}`);
      (error as Error & { status: number; body: string }).status = response.status;
      (error as Error & { status: number; body: string }).body = text;
      throw error;
    }
    return response.json() as Promise<{
      choices?: Array<{
        message?: {
          content?: string | null;
          tool_calls?: OpenAiApiToolCall[];
        };
      }>;
    }>;
  };

  const baseBody: Record<string, unknown> = {
    model: options.model,
    messages: options.messages,
    tools: options.tools,
    tool_choice: "auto",
  };
  if (options.temperature !== undefined) {
    baseBody.temperature = options.temperature;
  }

  let data: Awaited<ReturnType<typeof attempt>>;
  try {
    data = await attempt(baseBody);
  } catch (error) {
    const status = (error as { status?: number }).status;
    const body = (error as { body?: string }).body ?? "";
    // NOTE: some models reject temperature or require reasoning_effort instead
    if (status === 400 && (body.includes("temperature") || body.includes("reasoning_effort"))) {
      const retryBody = { ...baseBody };
      delete retryBody.temperature;
      if (body.includes("reasoning_effort")) {
        retryBody.reasoning_effort = "low";
      }
      data = await attempt(retryBody);
    } else {
      throw error;
    }
  }

  const message = data.choices?.[0]?.message;
  const toolCalls = message?.tool_calls?.map((call) => ({
    id: call.id,
    name: call.function.name,
    args: parseArgs(call.function.arguments),
  }));

  return {
    content: message?.content ?? undefined,
    toolCalls,
  };
}

/**
 * OpenAI Chat Completions UI-control agent (fetch-based; no hard openai SDK dep).
 */
export function createOpenAiAgent(plugin: UiPlugin, options: OpenAiAgentOptions) {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  if (!fetchImpl) {
    throw new Error("fetch is not available; pass options.fetch");
  }
  const baseUrl = options.baseUrl ?? "https://api.openai.com/v1";
  const systemPrompt = options.systemPrompt ?? UI_CONTROL_SYSTEM_PROMPT;

  return {
    async run(input: OpenAiAgentRunInput): Promise<OpenAiAgentRunResult> {
      await plugin.waitForClient(
        input.sessionId,
        input.waitTimeoutMs ?? options.defaultWaitTimeoutMs ?? 10_000,
      );

      const { tools, execute } = toOpenAiTools(plugin, input.sessionId, {
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
        complete: async (messages) =>
          openAiComplete({
            apiKey: options.apiKey,
            model: options.model,
            baseUrl,
            fetchImpl,
            messages: toOpenAiMessages(messages),
            tools,
            temperature: options.temperature,
            signal: input.signal,
          }),
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
