import { createServer } from "node:http";
import { PROTOCOL_VERSION } from "@xecutioner/protocol";
import { afterEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { createXecutioner } from "./create-xecutioner.js";
import { createXecutionerFromEnv } from "./create-xecutioner-from-env.js";
import { XecutionerError } from "./errors.js";
import { handleChat, handleStatus } from "./http-handlers.js";
import { createUiPlugin } from "./plugin.js";
import { createAllowlistPolicy, createDenyListPolicy, createRateLimitPolicy } from "./policy.js";

const openPlugins: Array<{ close: () => Promise<void> }> = [];

afterEach(async () => {
  while (openPlugins.length) {
    const item = openPlugins.pop();
    await item?.close();
  }
});

async function connectClient(url: string, sessionId: string): Promise<WebSocket> {
  const socket = new WebSocket(url);
  await new Promise<void>((resolve, reject) => {
    socket.once("open", () => resolve());
    socket.once("error", reject);
  });
  socket.send(
    JSON.stringify({
      type: "handshake",
      protocolVersion: PROTOCOL_VERSION,
      sessionId,
      capabilities: ["tap", "read_screen"],
    }),
  );
  await new Promise<void>((resolve, reject) => {
    const onMessage = (data: WebSocket.RawData) => {
      const message = JSON.parse(String(data)) as { type?: string };
      if (message.type === "handshake") {
        socket.off("message", onMessage);
        resolve();
      }
    };
    socket.on("message", onMessage);
    socket.once("error", reject);
  });
  return socket;
}

describe("XecutionerError", () => {
  it("preserves typed codes", () => {
    const error = new XecutionerError("TIMEOUT", "slow");
    expect(error.code).toBe("TIMEOUT");
    expect(XecutionerError.is(error)).toBe(true);
  });
});

describe("waitForClient", () => {
  it("resolves when the client connects", async () => {
    const plugin = createUiPlugin();
    openPlugins.push(plugin);
    const info = await plugin.listen({ port: 0, host: "127.0.0.1" });
    const port = info.port;
    expect(port).toBeTypeOf("number");

    const waiting = plugin.waitForClient("sess-1", 5_000);
    const socket = await connectClient(`ws://127.0.0.1:${port}/xecutioner`, "sess-1");
    await waiting;
    expect(plugin.isOnline("sess-1")).toBe(true);
    expect(plugin.listOnlineSessions()).toEqual(["sess-1"]);
    expect(plugin.requireOnlineSession("sess-1")).toBe("sess-1");
    socket.close();
  });

  it("times out when no client connects", async () => {
    const plugin = createUiPlugin();
    openPlugins.push(plugin);
    await plugin.listen({ port: 0, host: "127.0.0.1" });
    await expect(plugin.waitForClient("missing", 50)).rejects.toMatchObject({
      code: "TIMEOUT",
    });
  });
});

describe("policy presets", () => {
  it("allowlist denies unknown actions", async () => {
    const policy = createAllowlistPolicy({ actions: ["read_screen"] });
    const denied = await policy.authorize("s", {
      callId: "c1",
      action: "tap",
      idempotencyKey: "i1",
      deadline: Date.now() + 1000,
    });
    expect(denied.allow).toBe(false);

    const allowed = await policy.authorize("s", {
      callId: "c2",
      action: "read_screen",
      idempotencyKey: "i2",
      deadline: Date.now() + 1000,
    });
    expect(allowed.allow).toBe(true);
  });

  it("denylist blocks listed tools", async () => {
    const policy = createDenyListPolicy({ tools: ["ui_tap"] });
    const denied = await policy.authorize("s", {
      callId: "c1",
      action: "tap",
      idempotencyKey: "i1",
      deadline: Date.now() + 1000,
    });
    expect(denied.allow).toBe(false);
  });

  it("rate limit blocks concurrent commands", () => {
    const policy = createRateLimitPolicy({ maxConcurrentPerSession: 1 });
    expect(policy.begin("s").allow).toBe(true);
    expect(policy.begin("s").allow).toBe(false);
    policy.end("s");
    expect(policy.begin("s").allow).toBe(true);
  });
});

describe("createXecutioner", () => {
  it("no-ops listen when disabled", async () => {
    const x = createXecutioner({ enabled: false });
    openPlugins.push(x);
    expect(await x.listen()).toBeNull();
    expect(x.isStarted()).toBe(false);
    expect(() => x.requireOnlineSession("s")).toThrowError(XecutionerError);
  });

  it("attaches to an existing http server", async () => {
    const httpServer = createServer((_req, res) => {
      res.writeHead(200);
      res.end("ok");
    });
    await new Promise<void>((resolve) => {
      httpServer.listen(0, "127.0.0.1", () => resolve());
    });
    openPlugins.push({
      close: async () => {
        await new Promise<void>((resolve, reject) => {
          httpServer.close((error) => (error ? reject(error) : resolve()));
        });
      },
    });

    const x = createXecutioner({ server: httpServer, path: "/xecutioner" });
    openPlugins.push(x);
    const info = await x.listen();
    expect(info?.attached).toBe(true);
    expect(x.isStarted()).toBe(true);

    const address = httpServer.address();
    const port = address && typeof address === "object" ? address.port : 0;
    const socket = await connectClient(`ws://127.0.0.1:${port}/xecutioner`, "attached");
    await x.waitForClient("attached", 2_000);
    socket.close();
  });

  it("detaches upgrade handler on close without closing shared server", async () => {
    const httpServer = createServer((_req, res) => {
      res.writeHead(200);
      res.end("ok");
    });
    await new Promise<void>((resolve) => {
      httpServer.listen(0, "127.0.0.1", () => resolve());
    });
    openPlugins.push({
      close: async () => {
        await new Promise<void>((resolve, reject) => {
          httpServer.close((error) => (error ? reject(error) : resolve()));
        });
      },
    });

    const before = httpServer.listenerCount("upgrade");
    const x = createXecutioner({ server: httpServer, path: "/xecutioner" });
    await x.listen();
    expect(httpServer.listenerCount("upgrade")).toBe(before + 1);

    await x.close();
    expect(httpServer.listenerCount("upgrade")).toBe(before);
    expect(httpServer.listening).toBe(true);
  });

  it("reads env for createXecutionerFromEnv", async () => {
    const x = createXecutionerFromEnv({
      env: {
        XECUTIONER_ENABLED: "false",
        XECUTIONER_PORT: "9999",
      },
    });
    openPlugins.push(x);
    expect(x.enabled).toBe(false);
    expect(await x.listen()).toBeNull();
  });
});

describe("http handlers", () => {
  it("returns status", async () => {
    const x = createXecutioner({ enabled: true, defaultSessionId: "d1" });
    openPlugins.push(x);
    const result = handleStatus(x);
    expect(result.status).toBe(200);
    expect(result.body).toMatchObject({
      enabled: true,
      defaultSessionId: "d1",
      onlineSessions: [],
    });
  });

  it("maps client unavailable on chat", async () => {
    const x = createXecutioner({ enabled: true });
    openPlugins.push(x);
    const result = await handleChat({
      xecutioner: x,
      body: { goal: "do something", sessionId: "offline" },
      agent: {
        run: async () => {
          throw new XecutionerError("CLIENT_UNAVAILABLE", "offline");
        },
      },
    });
    expect(result.status).toBe(409);
    expect(result.body).toMatchObject({
      error: { code: "CLIENT_UNAVAILABLE" },
    });
  });
});
