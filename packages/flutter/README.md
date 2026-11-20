# xecutioner_flutter

Thin Flutter / Dart client for [Xecutioner](https://github.com/) in-app UI control.

Mirrors `@xecutioner/react-native`: WebSocket handshake, snapshot serialization, command executors, and navigation context. The host supplies the UI tree via `getRootNode`; no Semantics auto-walker in v1.

## Quickstart

```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final contextReader = createAppContextReader(
  app: const AppInfo(name: 'Shop', description: 'Orders and checkout'),
  navigation: createGoRouterAdapter(getRouter: () => router),
  screens: const [
    ScreenDefinition(id: 'orders', title: 'Orders', description: 'List of past orders'),
    ScreenDefinition(
      id: 'order_detail',
      title: 'Order detail',
      description: 'One order: items, status, tracking',
      params: {'orderId': 'string'},
    ),
  ],
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

## Package layout

| Path | Role |
| --- | --- |
| `lib/src/protocol/` | Wire types, constants, helpers, validation (Dart port of `@xecutioner/protocol`) |
| `lib/src/client.dart` | WebSocket client |
| `lib/src/snapshot.dart` | Host tree → protocol snapshot |
| `lib/src/executors.dart` | Command execution |
| `lib/src/navigation/` | Context reader + go_router-like adapter |

Protocol JSON Schema remains the source of truth in `packages/protocol/schemas/protocol.json`. Regenerate Dart types with:

```bash
node scripts/generate_dart_types.mjs
```

## Tests

```bash
dart pub get
dart test
```
