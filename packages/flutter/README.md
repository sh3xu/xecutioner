# xecutioner_flutter

Thin Flutter / Dart client for Xecutioner in-app UI control.

Mirrors `@xecutioner/react-native`: WebSocket handshake, snapshot serialization, command executors, and navigation context. The host supplies the UI tree via `getRootNode`; no Semantics auto-walker in v1.

**Full guides:** [Flutter usage](../../docs/flutter.md) · [Backend usage](../../docs/backend.md)

## Install

```yaml
dependencies:
  xecutioner_flutter:
    path: ../../packages/flutter
```

## Quickstart

```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final contextReader = createAppContextReader(
  CreateAppContextReaderOptions(
    app: const AppInfo(name: 'Shop', description: 'Orders and checkout'),
    navigation: createGoRouterAdapter(
      CreateGoRouterAdapterOptions(getRouter: () => router),
    ),
    screens: const [
      ScreenDefinition(
        id: 'orders',
        title: 'Orders',
        description: 'List of past orders',
      ),
      ScreenDefinition(
        id: 'order_detail',
        title: 'Order detail',
        description: 'One order: items, status, tracking',
        params: {'orderId': 'string'},
      ),
    ],
  ),
);

final client = createUiClient(
  UiClientOptions(
    url: 'ws://localhost:8787/xecutioner',
    sessionId: sessionId, // must match backend tool binding
    hooks: HostHooks(
      getRootNode: () => hostTree,
      performAction: (request) async { /* tap / input / scroll */ },
      contextReader: contextReader,
      onAiActing: (acting) { /* optional banner */ },
    ),
  ),
);
await client.connect();
```

## What you implement

| Hook | Required | Role |
| --- | --- | --- |
| `getRootNode` | yes | Return current screen as `HostUiNode` tree (stable `testID`s) |
| `performAction` | for live UI | Apply tap / scroll / input to the real widgets |
| `contextReader` / `navigation` | for navigate tools | Screen map + go_router (or custom) adapter |
| `onAiActing` | no | Show “AI acting” affordance |
| `onApprovalRequest` | no | Gate sensitive actions |

## Pair with the backend

1. Start `@xecutioner/server` and `listen({ port: 8787 })`.
2. Bind tools with the **same** `sessionId`: `toVercelAiTools(ui, sessionId)`.
3. Connect this client to `ws://host:8787/xecutioner` with that `sessionId`.

See [docs/backend.md](../../docs/backend.md).

## Demo / tests

```bash
cd packages/flutter && dart pub get && dart test
cd examples/flutter-chat-demo && dart pub get && dart run bin/run_demo.dart
```

## Package layout

| Path | Role |
| --- | --- |
| `lib/src/protocol/` | Wire types, constants, helpers, validation |
| `lib/src/client.dart` | WebSocket client |
| `lib/src/snapshot.dart` | Host tree → protocol snapshot |
| `lib/src/executors.dart` | Command execution |
| `lib/src/navigation/` | Context reader + go_router-like adapter |

Regenerate schema checklist after protocol changes:

```bash
node scripts/generate_dart_types.mjs
# or: pnpm --filter @xecutioner/protocol generate:dart
```
