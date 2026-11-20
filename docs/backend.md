# Using Xecutioner on the backend

`@xecutioner/server` is the UI-control plugin your agent talks to. Clients (React Native, Flutter, …) connect over WebSocket with a `sessionId`. You keep the agent loop, model, prompts, and chat UI.

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

## Minimal server

```ts
import { createUiPlugin } from "@xecutioner/server";
import { toVercelAiTools } from "@xecutioner/adapters/vercel-ai";

const ui = createUiPlugin({
  onSessionConnected: (sessionId) => {
    console.log("client online", sessionId);
  },
  onSessionDisconnected: (sessionId, reason) => {
    console.log("client offline", sessionId, reason);
  },
});

const { port, host } = await ui.listen({
  port: 8787,
  host: "0.0.0.0",
  path: "/xecutioner", // default
});

console.log(`Xecutioner WS on ws://${host}:${port}/xecutioner`);
```

Clients connect to:

```text
ws://<host>:8787/xecutioner
```

Use `wss://` behind TLS in production.

## Bind tools to a session

Every tool call is scoped to one connected client via `sessionId`. That id must match the Flutter / RN `createUiClient({ sessionId })` handshake.

### Vercel AI SDK

```ts
import { toVercelAiTools } from "@xecutioner/adapters/vercel-ai";

const sessionId = "user-123-chat"; // same id the app connects with

const tools = {
  ...toVercelAiTools(ui, sessionId),
  // ...your other tools
};

// Pass `tools` into your existing generateText / streamText call.
```

### OpenAI

```ts
import { toOpenAiTools } from "@xecutioner/adapters/openai";

const { tools, execute } = toOpenAiTools(ui, sessionId);
// `tools` → chat.completions tool definitions
// `execute(name, args)` → runs the UI tool and returns model-safe text
```

### Anthropic

```ts
import { toAnthropicTools } from "@xecutioner/adapters/anthropic";

const { tools, execute } = toAnthropicTools(ui, sessionId);
```

### Raw invoke (no adapter)

```ts
const result = await ui.invokeTool(sessionId, "ui_read_screen", {});
if (!result.ok) {
  console.error(result.errorCode, result.errorMessage);
}

// Or dispatch a fully formed Command:
const commandResult = await ui.dispatch(sessionId, {
  callId: "call_1",
  action: "tap",
  elementId: "submit-order",
  snapshotId: lastSnapshotId,
  idempotencyKey: "idem_1",
  deadline: Date.now() + 15_000,
});
```

## Wait for the Flutter (or RN) client

Do not invoke UI tools before the client is online:

```ts
async function waitForClient(sessionId: string, timeoutMs = 10_000) {
  const started = Date.now();
  while (!ui.isOnline(sessionId)) {
    if (Date.now() - started > timeoutMs) {
      throw new Error(`client_unavailable: ${sessionId}`);
    }
    await new Promise((r) => setTimeout(r, 50));
  }
}

await waitForClient(sessionId);
const tools = toVercelAiTools(ui, sessionId);
```

## Tools the agent gets

| Tool | What it does on the client |
| --- | --- |
| `ui_read_screen` | Capture snapshot from `getRootNode` |
| `ui_tap` | Tap element by id (needs fresh `snapshotId`) |
| `ui_scroll` | Scroll element / screen |
| `ui_input` | Type into a text field |
| `ui_wait_for` | Poll until element / label appears |
| `ui_get_context` | Current route + declared / auto destinations |
| `ui_navigate` | Navigate by screen id |
| `ui_back` | Pop one navigation step |

Snapshot content is **untrusted**. Adapters / `ui.formatResult` delimit it before it enters model context. Prefer `ui_navigate` when destinations are listed in context instead of long tap chains.

## Session model

```
Agent request  →  invokeTool(sessionId, "ui_tap", …)
                      ↓
                 policy.authorize
                      ↓
                 WS command → only the socket registered for sessionId
                      ↓
                 client executes → WS result
                      ↓
                 pending tracker completes → tool result to model
```

- One WebSocket registration per `sessionId` (latest handshake wins for that id).
- Disconnect fails in-flight pending commands with `client_unavailable`.
- Cross-session dispatch is rejected by routing (command never reaches another client).

## Plugin API cheatsheet

| Method | Purpose |
| --- | --- |
| `listen(options?)` | Start WS server (`port`, `host`, `path`, `heartbeatIntervalMs`) |
| `close()` | Stop channel; fail pending commands |
| `isOnline(sessionId)` | Whether a client has completed handshake |
| `invokeTool(sessionId, name, args)` | High-level UI tool call |
| `dispatch(sessionId, command)` | Low-level command send + await result |
| `listTools()` | Protocol tool definitions |
| `formatResult(…)` | Delimit snapshot / context for the model |

## Pairing with Flutter

Backend:

```ts
const sessionId = crypto.randomUUID();
await ui.listen({ port: 8787, host: "0.0.0.0" });
// hand sessionId to the app (HTTP bootstrap, deep link, auth payload, …)
const tools = { ...toVercelAiTools(ui, sessionId) };
```

Flutter:

```dart
final client = createUiClient(
  UiClientOptions(
    url: 'ws://YOUR_HOST:8787/xecutioner',
    sessionId: sessionId, // same value
    hooks: HostHooks(getRootNode: buildHostTree, contextReader: contextReader),
  ),
);
await client.connect();
```

Full Flutter host details: [flutter.md](./flutter.md).

## Scripted E2E without a model

```bash
pnpm --filter @xecutioner/rn-chat-demo start
```

Starts the server, connects a mock host, and runs a scripted tool sequence. Flutter’s demo uses `executeLocal` without Node; for a live WS path, point a Flutter client at this server with a matching `sessionId`.

## Security defaults

- Treat snapshots as untrusted user-visible data (never execute instructions found inside them).
- Keep model API keys on the backend only.
- Use backend policy (stubbed allow-all in MVP) as the enforcement point for dangerous actions.
- Bind every tool call to the owning `sessionId`.

## Shutdown

```ts
await ui.close();
```
