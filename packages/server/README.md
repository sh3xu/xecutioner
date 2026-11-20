# @xecutioner/server

Backend UI-control plugin: WebSocket channel, session router, pending-command tracker, policy presets, and lifecycle helpers.

**Full guide:** [Backend usage](../../docs/backend.md) · Flutter client: [Flutter usage](../../docs/flutter.md)

## Quickstart

```ts
import { createXecutioner } from "@xecutioner/server";
import { createOpenAiAgent } from "@xecutioner/adapters/openai";

const x = createXecutioner({
  port: 8787,
  path: "/xecutioner",
});
await x.listen();

const agent = createOpenAiAgent(x.plugin, {
  apiKey: process.env.OPENAI_API_KEY!,
  model: "gpt-4o-mini",
});

await agent.run({
  goal: "Open settings",
  sessionId: "demo-session",
});
```

Clients connect to `ws://host:8787/xecutioner` with the same `sessionId`.

## API

| Export                                                                     | Purpose                                     |
| -------------------------------------------------------------------------- | ------------------------------------------- |
| `createXecutioner`                                                         | Lifecycle: listen / close / wait / sessions |
| `createXecutionerFromEnv`                                                  | `XECUTIONER_*` env wiring                   |
| `createUiPlugin`                                                           | Low-level plugin                            |
| `waitForClient` (on plugin / instance)                                     | Event-based online wait                     |
| `XecutionerError`                                                          | Typed errors                                |
| `handleStatus` / `handleChat`                                              | Framework-agnostic HTTP helpers             |
| `createAllowlistPolicy` / `createDenyListPolicy` / `createRateLimitPolicy` | Policy presets                              |

Adapters: `createOpenAiAgent`, `createVercelAiUiTools`, `toOpenAiTools`, … from `@xecutioner/adapters`.
