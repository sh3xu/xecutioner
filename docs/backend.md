# Using Xecutioner on the backend

`@xecutioner/server` owns transport, sessions, policy, and wait helpers.  
`@xecutioner/adapters` owns tool binding plus optional UI-tool agent runners.  
Your app keeps routes, auth, i18n, and product rules.

Package: [`packages/server`](../packages/server)  
Adapters: [`packages/adapters`](../packages/adapters)  
Protocol: [`packages/protocol`](../packages/protocol)

## Install

```bash
pnpm add @xecutioner/server @xecutioner/adapters
# workspace / monorepo:
# "@xecutioner/server": "workspace:*"
# "@xecutioner/adapters": "workspace:*"
```

## Target DX (~20–40 lines)

```ts
import { createXecutioner } from "@xecutioner/server";
import { createOpenAiAgent } from "@xecutioner/adapters/openai";

const x = createXecutioner({
  server: httpServer, // or { port: 8787 }
  path: "/xecutioner",
  logger: (level, msg, meta) => logger[level](meta, msg),
});

await x.listen();

const agent = createOpenAiAgent(x.plugin, {
  apiKey: process.env.OPENAI_API_KEY!,
  model: "gpt-4o-mini",
});

const result = await agent.run({
  goal: "Open settings and enable dark mode",
  sessionId: "booking-abc",
  maxSteps: 12,
  waitTimeoutMs: 10_000,
});
```

Mint `sessionId` on the backend and pass the same value into Flutter `Xecutioner.init` / RN `createUiClient`. Do not rely on client auto-generated `xec_*` ids for tool binding.

## Lifecycle helpers

| API                                                   | Purpose                                                             |
| ----------------------------------------------------- | ------------------------------------------------------------------- |
| `createXecutioner(opts)`                              | Singleton-style wrapper: listen / close / wait / sessions           |
| `createXecutionerFromEnv({ prefix, server, logger })` | Reads `XECUTIONER_ENABLED\|PORT\|HOST\|PATH`                        |
| `x.listen()`                                          | Dedicated port **or** attach to existing `http.Server` via `server` |
| `x.waitForClient(sessionId, timeoutMs?)`              | Event-based wait (throws typed `TIMEOUT`)                           |
| `x.listOnlineSessions()`                              | Multi-device / multi-booking status                                 |
| `x.requireOnlineSession(id?)`                         | Uses `defaultSessionId` when omitted                                |

Low-level `createUiPlugin` remains available if you need the raw plugin only.

## Typed errors

```ts
import { XecutionerError } from "@xecutioner/server";

try {
  await x.waitForClient(sessionId);
} catch (error) {
  if (XecutionerError.is(error) && error.code === "CLIENT_UNAVAILABLE") {
    // map to your ApiError / i18n
  }
}
```

Codes: `CLIENT_UNAVAILABLE` | `NOT_STARTED` | `TIMEOUT` | `POLICY_DENIED` | `UNKNOWN_TOOL` | `PLUGIN_CLOSED`.

## Policy presets

```ts
import {
  createAllowlistPolicy,
  createDenyListPolicy,
  createRateLimitPolicy,
  createXecutioner,
} from "@xecutioner/server";

const x = createXecutioner({
  policy: createRateLimitPolicy({
    maxConcurrentPerSession: 2,
    maxCommandsPerMinute: 60,
    inner: createAllowlistPolicy({
      tools: [
        "ui_read_screen",
        "ui_get_context",
        "ui_navigate",
        "ui_tap",
        "ui_input",
        "ui_scroll",
        "ui_wait_for",
        "ui_back",
      ],
    }),
  }),
});
```

`createAllowAllPolicy` remains for local demos only.

## Bind tools without an agent runner

### Vercel AI SDK

```ts
import { createVercelAiUiTools } from "@xecutioner/adapters/vercel-ai";

await x.waitForClient(sessionId);
const tools = {
  ...createVercelAiUiTools(x.plugin, sessionId),
};
```

### OpenAI / Anthropic tool defs only

```ts
import { toOpenAiTools } from "@xecutioner/adapters/openai";
import { toAnthropicTools } from "@xecutioner/adapters/anthropic";

const { tools, execute } = toOpenAiTools(x.plugin, sessionId);
```

### Shared loop

```ts
import { runWithTools } from "@xecutioner/adapters";
```

Default system prompt: `UI_CONTROL_SYSTEM_PROMPT` from `@xecutioner/protocol` (override per agent).

## Optional HTTP handlers (framework-agnostic)

Auth stays in your app. Mount these behind your middleware:

```ts
import { handleStatus, handleChat } from "@xecutioner/server";

app.get("/executioner/status", (_req, res) => {
  const { status, body } = handleStatus(x);
  res.status(status).json(body);
});

app.post("/executioner/chat", async (req, res) => {
  const { status, body } = await handleChat({
    xecutioner: x,
    agent,
    body: req.body,
  });
  res.status(status).json(body);
});
```

`POST` body: `{ message | goal, sessionId?, maxSteps?, waitTimeoutMs? }`.

## Tools the agent gets

| Tool             | What it does on the client                            |
| ---------------- | ----------------------------------------------------- |
| `ui_read_screen` | Capture snapshot from `getRootNode` / action registry |
| `ui_tap`         | Tap element by id (needs fresh `snapshotId`)          |
| `ui_scroll`      | Scroll element / screen                               |
| `ui_input`       | Type into a text field                                |
| `ui_wait_for`    | Poll until element / label appears                    |
| `ui_get_context` | Current route + declared / auto destinations          |
| `ui_navigate`    | Navigate by screen id                                 |
| `ui_back`        | Pop one navigation step                               |

Snapshot content is **untrusted**. Adapters / `ui.formatResult` delimit it before it enters model context.

## Session model

```
Agent request  →  waitForClient(sessionId)
                      ↓
                 invokeTool / agent.run
                      ↓
                 policy.authorize
                      ↓
                 WS command → only the socket registered for sessionId
                      ↓
                 client executes → WS result
```

- One WebSocket registration per `sessionId` (latest handshake wins).
- Disconnect fails in-flight pending commands with `CLIENT_UNAVAILABLE`.
- Cross-session dispatch is rejected by routing.

## Pairing with Flutter

Backend owns the id:

```ts
const sessionId = crypto.randomUUID();
await x.listen({ port: 8787, host: "0.0.0.0" });
// hand sessionId to the app (HTTP bootstrap, deep link, auth payload, …)
```

Flutter:

```dart
await Xecutioner.init(XecutionerConfig(
  url: 'ws://YOUR_HOST:8787/xecutioner',
  sessionId: sessionId, // same value
  // navigation + ExecutionerActions …
));
```

Full Flutter host details: [flutter.md](./flutter.md).

## What stays in your backend

1. Thin `createXecutioner` + logger wiring
2. Route auth + i18n mapping for `XecutionerError.code`
3. Product rules (which booking owns which `sessionId`)
4. Model API keys

## Scripted E2E without a model

```bash
pnpm --filter @xecutioner/rn-chat-demo start
```

## Shutdown

```ts
await x.close();
```
