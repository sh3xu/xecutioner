import type { UiPlugin } from "@xecutioner/server";
import { describe, expect, it, vi } from "vitest";
import { listDefinitions } from "./common.js";
import { createOpenAiAgent } from "./openai-agent.js";
import { runWithTools } from "./run-with-tools.js";
import { createVercelAiUiTools } from "./vercel-ai.js";

function mockPlugin(overrides?: Partial<UiPlugin>): UiPlugin {
  return {
    listen: async () => ({ port: 0, host: "127.0.0.1", path: "/xecutioner", attached: false }),
    close: async () => undefined,
    isStarted: () => true,
    getListenInfo: () => ({ port: 0, host: "127.0.0.1", path: "/xecutioner", attached: false }),
    isOnline: () => true,
    listOnlineSessions: () => ["s1"],
    requireOnlineSession: (id) => id ?? "s1",
    waitForClient: async () => undefined,
    dispatch: async (_sessionId, command) => ({ callId: command.callId, ok: true }),
    invokeTool: async () => ({
      content: '{"ok":true}',
      result: { callId: "c1", ok: true },
    }),
    listTools: () => listDefinitions(),
    formatResult: () => "",
    router: {} as UiPlugin["router"],
    pending: {} as UiPlugin["pending"],
    ...overrides,
  };
}

describe("runWithTools", () => {
  it("runs tool calls then returns final answer", async () => {
    const execute = vi.fn(async () => "tool-result");
    let calls = 0;
    const result = await runWithTools({
      messages: [{ role: "user", content: "goal" }],
      tools: [{ name: "ui_tap", description: "tap", parameters: {} }],
      execute,
      maxSteps: 5,
      complete: async () => {
        calls += 1;
        if (calls === 1) {
          return {
            toolCalls: [{ id: "1", name: "ui_tap", args: { elementId: "a" } }],
          };
        }
        return { content: "done" };
      },
    });

    expect(execute).toHaveBeenCalledWith("ui_tap", { elementId: "a" });
    expect(result.answer).toBe("done");
    expect(result.steps).toBe(2);
    expect(result.toolTrace).toHaveLength(1);
  });
});

describe("createOpenAiAgent", () => {
  it("waits for client and loops with mocked fetch", async () => {
    const waitForClient = vi.fn(async () => undefined);
    const plugin = mockPlugin({ waitForClient });

    const fetchImpl = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          choices: [
            {
              message: {
                content: "All set",
                tool_calls: undefined,
              },
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    });

    const agent = createOpenAiAgent(plugin, {
      apiKey: "test",
      model: "gpt-4o-mini",
      fetch: fetchImpl as unknown as typeof fetch,
    });

    const result = await agent.run({
      goal: "Open settings",
      sessionId: "booking-1",
      maxSteps: 3,
    });

    expect(waitForClient).toHaveBeenCalledWith("booking-1", 10_000);
    expect(result.answer).toBe("All set");
    expect(result.sessionId).toBe("booking-1");
    expect(fetchImpl).toHaveBeenCalled();
  });
});

describe("createVercelAiUiTools", () => {
  it("aliases toVercelAiTools", () => {
    const tools = createVercelAiUiTools(mockPlugin(), "s1");
    expect(Object.keys(tools)).toHaveLength(8);
  });
});
