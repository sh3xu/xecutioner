import type { UiPlugin } from "@xecutioner/server";
import { describe, expect, it } from "vitest";
import { toAnthropicTools } from "./anthropic.js";
import { listDefinitions } from "./common.js";
import { toOpenAiTools } from "./openai.js";
import { toVercelAiTools } from "./vercel-ai.js";

function mockPlugin(): UiPlugin {
  return {
    listen: async () => ({ port: 0, host: "127.0.0.1", path: "/xecutioner", attached: false }),
    close: async () => undefined,
    isStarted: () => true,
    getListenInfo: () => ({ port: 0, host: "127.0.0.1", path: "/xecutioner", attached: false }),
    isOnline: () => true,
    listOnlineSessions: () => ["s1"],
    requireOnlineSession: (id) => id ?? "s1",
    waitForClient: async () => undefined,
    dispatch: async (sessionId, command) => ({
      callId: command.callId,
      ok: true,
      snapshot: {
        snapshotId: "s1",
        capturedAt: Date.now(),
        elements: [],
        screen: sessionId,
      },
    }),
    invokeTool: async (_sessionId, _name, _args) => ({
      content: '{"ok":true}',
      result: { callId: "c1", ok: true },
    }),
    listTools: () => listDefinitions(),
    formatResult: () => "",
    router: {} as UiPlugin["router"],
    pending: {} as UiPlugin["pending"],
  };
}

describe("adapters", () => {
  it("exports all UI tools for each adapter", () => {
    const plugin = mockPlugin();
    expect(Object.keys(toVercelAiTools(plugin, "s1"))).toHaveLength(8);
    expect(toOpenAiTools(plugin, "s1").tools).toHaveLength(8);
    expect(toAnthropicTools(plugin, "s1").tools).toHaveLength(8);
  });
});
