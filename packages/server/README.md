# @xecutioner/server

Backend UI-control plugin: WebSocket channel, session router, pending-command tracker, and `ui_*` tool invoke.

**Full guide:** [Backend usage](../../docs/backend.md) · Flutter client: [Flutter usage](../../docs/flutter.md)

## Quickstart

```ts
import { createUiPlugin } from "@xecutioner/server";
import { toVercelAiTools } from "@xecutioner/adapters/vercel-ai";

const ui = createUiPlugin();
await ui.listen({ port: 8787 });

const sessionId = "demo-session";
const tools = {
  ...toVercelAiTools(ui, sessionId),
};
```

Clients (RN / Flutter) connect to `ws://host:8787/xecutioner` with the same `sessionId`.

## API

| Method | Purpose |
| --- | --- |
| `listen` | Start WS (`port`, `host`, `path`) |
| `invokeTool` | Run a named `ui_*` tool for a session |
| `dispatch` | Send a raw `Command` and await `CommandResult` |
| `isOnline` | Whether the session’s client is connected |
| `close` | Shut down |

Adapters: `toVercelAiTools`, `toOpenAiTools`, `toAnthropicTools` from `@xecutioner/adapters`.
