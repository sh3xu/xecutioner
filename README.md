# Xecutioner

**Install once, and your existing agent can operate your app on every client stack.**

Xecutioner is a backend plugin plus thin client libraries that give any developer’s AI agent the ability to **see and operate their app’s UI** (tap, scroll, input, read screen). You keep your chat UI and product logic. Xecutioner owns UI tools, sessions, policy, and optional UI-tool agent runners.

## Positioning

| You own                       | Xecutioner owns                                             |
| ----------------------------- | ----------------------------------------------------------- |
| Chat UI, product routes, auth | UI tools, protocol, session routing, execution              |
| App business logic            | Snapshot serialization & action executors                   |
| Host approval UI rendering    | When approval is required (policy)                          |
| Model API keys                | Optional `createOpenAiAgent` / `runWithTools` UI-tool loops |

### Non-goals

- Chat UI or bubbles
- Voice
- Model hosting
- Memory or RAG
- OS-level control of other apps
- Full agent products / planners (optional runners are UI-tool loops only)

## Architecture

```
Developer's agent (their loop, model, chat UI)
   │  tools: { ...ui.tools(sessionId), ...theirTools }
   ▼
@xecutioner/server
   ├─ Tool definitions (ui_tap, ui_scroll, ui_input, ui_read_screen, ui_wait_for)
   ├─ Session router
   ├─ Policy stub (Phase 3: full engine)
   ├─ Pending-command tracker
   └─ WebSocket channel
   ▼
@xecutioner/react-native | xecutioner_flutter
   ├─ Snapshot serializer
   ├─ Executors (tap, scroll, input, wait_for)
   └─ Host hooks (AI acting, approval)
```

## Monorepo

```
packages/
  protocol/       # JSON Schema, generated types, shared helpers
  server/         # plugin core, router, WS channel, tools
  adapters/       # vercel-ai, openai, anthropic exporters
  react-native/   # RN / host-tree client
  flutter/        # Dart / Flutter client (pub package; outside pnpm)
  testing/        # mocks, conformance fixtures, eval stubs
examples/
  rn-chat-demo/       # end-to-end scripted demo (WS + server)
  flutter-chat-demo/  # Dart client scripted demo (executeLocal)
spec/
  protocol-v0.1.md
```

Tooling: **pnpm** workspaces, **Turborepo**, **Biome**, **Vitest**, **Changesets**. Flutter client uses **Dart** (`dart pub` / `dart test`) and is not part of the pnpm workspace.

## Docs

| Guide                                          | Audience                                                             |
| ---------------------------------------------- | -------------------------------------------------------------------- |
| [docs/backend.md](docs/backend.md)             | Start the server, bind `ui_*` tools to your agent, session pairing   |
| [docs/flutter.md](docs/flutter.md)             | Install the Dart client, host tree, go_router, connect to the server |
| [spec/protocol-v0.1.md](spec/protocol-v0.1.md) | Wire protocol                                                        |

## Quickstart

```bash
pnpm install
pnpm build
pnpm test
```

### Server

```ts
import { createXecutioner } from "@xecutioner/server";
import { createOpenAiAgent } from "@xecutioner/adapters/openai";

const x = createXecutioner({ port: 8787 });
await x.listen();

const agent = createOpenAiAgent(x.plugin, {
  apiKey: process.env.OPENAI_API_KEY!,
  model: "gpt-4o-mini",
});

await agent.run({ goal: "Open settings", sessionId });
```

### React Native (thin client)

```ts
import {
  createAppContextReader,
  createReactNavigationAdapter,
  createUiClient,
} from "@xecutioner/react-native";

const contextReader = createAppContextReader({
  app: { name: "Shop", description: "Orders and checkout" },
  navigation: createReactNavigationAdapter({ getRef: () => navigationRef }),
  screens: [
    { id: "orders", title: "Orders", description: "List of past orders" },
    {
      id: "order_detail",
      title: "Order detail",
      description: "One order: items, status, tracking",
      params: { orderId: "string" },
    },
  ],
});

const client = createUiClient({
  url: "ws://localhost:8787/xecutioner",
  sessionId,
  hooks: {
    getRootNode: () => hostTree,
    contextReader,
    onAiActing: (acting) => setBanner(acting),
  },
});
await client.connect();
```

### Flutter (thin client)

```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final contextReader = createAppContextReader(
  CreateAppContextReaderOptions(
    app: const AppInfo(name: 'Shop', description: 'Orders and checkout'),
    navigation: createGoRouterAdapter(
      CreateGoRouterAdapterOptions(getRouter: () => router),
    ),
    screens: const [
      ScreenDefinition(id: 'orders', title: 'Orders', description: 'List of past orders'),
    ],
  ),
);

final client = createUiClient(
  UiClientOptions(
    url: 'ws://localhost:8787/xecutioner',
    sessionId: sessionId,
    hooks: HostHooks(
      getRootNode: () => hostTree,
      contextReader: contextReader,
      onAiActing: (acting) => setBanner(acting),
    ),
  ),
);
await client.connect();
```

```bash
cd packages/flutter && dart pub get && dart test
cd examples/flutter-chat-demo && dart pub get && dart run bin/run_demo.dart
```

### Demo (no device / no API key)

```bash
pnpm --filter @xecutioner/rn-chat-demo start
```

Runs a WebSocket server, connects a mock host UI tree, and a **scripted agent** completes a multi-screen task via UI tools.

```bash
cd examples/flutter-chat-demo && dart run bin/run_demo.dart
```

Runs the same multi-screen task against the Dart client via `executeLocal` (no Node server required).

## Tools

| Tool             | Purpose                                  |
| ---------------- | ---------------------------------------- |
| `ui_read_screen` | Capture compact UI snapshot (untrusted)  |
| `ui_tap`         | Tap element by id                        |
| `ui_scroll`      | Scroll element / screen                  |
| `ui_input`       | Type into a text field                   |
| `ui_wait_for`    | Wait for element / label                 |
| `ui_get_context` | Current route/stack + known destinations |
| `ui_navigate`    | Go directly to a screen by id            |
| `ui_back`        | Pop one navigation step                  |

Adapters export the same definitions for **Vercel AI SDK**, **OpenAI**, and **Anthropic**.

## Protocol essentials

- Snapshot: `snapshotId`, screen/route, elements (`id`, `role`, `label`, `value`, `state`, `bounds`, `actions`, `children`)
- Commands: `callId`, `snapshotId`, `idempotencyKey`, `deadline`
- Errors: `stale_snapshot`, `element_not_found`, `not_actionable`, `blocked_by_policy`, `timeout`, `client_unavailable`
- Element addressing: developer stable IDs first, generated refs as fallback
- See [spec/protocol-v0.1.md](spec/protocol-v0.1.md)

## Security notes

- **Screen content is untrusted.** Snapshots are delimited and labeled before they enter model context.
- **Session binding.** Commands go only to the client that owns the session.
- **Backend policy** (stubbed in MVP) is the enforcement point — not the prompt or the client.
- Redact sensitive fields with `xecutionerRedact` on host nodes.

## Roadmap (after MVP)

1. **Reliability** — stale detection hardening, wait_for polish, virtualized lists, semantic app tools, readiness audit
2. **Safety** — full policy engine, approvals, redaction rules, injection suite, audit log, kill switch
3. **Transport & scale** — stateless piggyback, Redis routing, MCP wrapper
4. **Clients** — Android, iOS, web (conformance-gated); Flutter client (`xecutioner_flutter`) ships as a Dart package in `packages/flutter`
5. **DX** — docs, trace viewer, OpenTelemetry, publishing

## Success metrics

- Time to first successful AI-driven tap under 15 minutes
- Same backend across client stacks without backend changes
- Eval suite task success rate (targets set in Phase 2)
- Zero lost/duplicated actions under multi-instance load tests

## Contributing

1. Use **pnpm** and **Biome** only.
2. Put shared logic in `@xecutioner/protocol` helpers — **never duplicate** functions; extend with optional params instead.
3. Change JSON Schema before TypeScript wire types.
4. Keep clients free of agent/model code.
5. Add Vitest coverage for protocol and dispatch paths.

```bash
pnpm lint
pnpm test
pnpm build
```
