# Using Xecutioner in Flutter

The Flutter / Dart client (`xecutioner_flutter`) is a thin host: it connects to `@xecutioner/server` over WebSocket, serializes the UI tree you supply, and executes tap / scroll / input / navigate commands. You keep your app UI, navigation, and agent loop.

Package path: [`packages/flutter`](../packages/flutter)  
Demo: [`examples/flutter-chat-demo`](../examples/flutter-chat-demo)

## Install

Path dependency (monorepo):

```yaml
# pubspec.yaml
dependencies:
  xecutioner_flutter:
    path: ../packages/flutter # or your relative path
```

```bash
dart pub get
```

There is no hard dependency on `go_router` or the Flutter SDK for the core client. Unit tests and demos run as pure Dart. In a Flutter app, wrap your real `GoRouter` with the duck-typed `GoRouterLike` surface (or use `createGoRouterAdapter` with a thin adapter).

## End-to-end flow

```
Your agent (Node)  --tools-->  @xecutioner/server (WS :8787/xecutioner)
                                      |
                               same sessionId
                                      |
                               xecutioner_flutter client in the app
                                      |
                         getRootNode / performAction / navigation
```

1. Backend listens and registers tools for a `sessionId`.
2. Flutter client connects with the **same** `sessionId`.
3. Agent calls `ui_*` tools; server forwards commands; client returns results.

## Minimal integration

```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

late final UiClient client;

Future<void> startXecutioner({
  required String sessionId,
  required GoRouterLike router,
}) async {
  final contextReader = createAppContextReader(
    CreateAppContextReaderOptions(
      app: const AppInfo(
        name: 'Shop',
        description: 'Orders and checkout',
      ),
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
          reachableFrom: ['orders'],
        ),
        ScreenDefinition(
          id: 'checkout',
          title: 'Checkout',
          description: 'Enter email and submit the order',
          reachableFrom: ['order_detail'],
        ),
      ],
    ),
  );

  client = createUiClient(
    UiClientOptions(
      url: 'ws://127.0.0.1:8787/xecutioner', // use wss:// in production
      sessionId: sessionId,
      hooks: HostHooks(
        getRootNode: buildHostTree,
        contextReader: contextReader,
        performAction: onPerformAction,
        onAiActing: (acting) {
          // Optional: show "AI is acting" banner
        },
        onApprovalRequest: (payload) async {
          // Optional: prompt the user; return false to block
          return true;
        },
      ),
    ),
  );

  await client.connect();
}

void stopXecutioner() {
  client.disconnect();
}
```

## Host UI tree (`getRootNode`)

v1 does **not** walk Flutter Semantics automatically. You build a `HostUiNode` tree (or a subset of the current screen) and return it from `getRootNode`.

Stable ids (`testID`) are what the model taps:

```dart
HostUiNode buildHostTree() {
  return HostUiNode(
    testID: 'screen-checkout',
    accessibilityRole: 'summary',
    accessibilityLabel: 'Checkout',
    children: [
      HostUiNode(
        testID: 'email-input',
        accessibilityRole: 'textbox',
        accessibilityLabel: 'Email',
        props: {'value': currentEmail},
        accessibilityValue: AccessibilityValue(text: currentEmail),
      ),
      HostUiNode(
        testID: 'submit-order',
        accessibilityRole: 'button',
        accessibilityLabel: 'Submit order',
      ),
      HostUiNode(
        testID: 'password',
        accessibilityRole: 'textbox',
        accessibilityLabel: 'Password',
        xecutionerRedact: true, // label becomes [redacted]; value omitted
        accessibilityValue: AccessibilityValue(text: secret),
      ),
    ],
  );
}
```

| Field                                       | Purpose                                                   |
| ------------------------------------------- | --------------------------------------------------------- |
| `testID`                                    | Stable element id (preferred over generated `ref_*`)      |
| `accessibilityRole`                         | Maps to actions (`button` → tap, `textbox` → input, etc.) |
| `accessibilityLabel` / `accessibilityValue` | What the model sees                                       |
| `xecutionerRedact`                          | Redact sensitive fields in snapshots                      |
| `children`                                  | Nested tree                                               |
| `actions`                                   | Optional explicit actions override                        |

## Applying actions (`performAction`)

Without `performAction`, only in-memory `input` mutation on the host node is applied. For a real app, implement the hook:

```dart
Future<void> onPerformAction(PerformActionRequest request) async {
  switch (request.action) {
    case 'tap':
      await handleTap(request.elementId);
    case 'input':
      await handleInput(request.elementId, request.text ?? '');
    case 'scroll':
      await handleScroll(
        request.elementId,
        direction: request.direction,
        amount: request.amount,
      );
  }
}
```

## Navigation

### Declared screen map

Register screens the agent should know about (`ui_get_context` / `ui_navigate`). Use stable `id` values that match what you pass to `navigate`.

### go_router adapter

`createGoRouterAdapter` takes a `GoRouterLike` (duck-typed; no hard `go_router` dependency):

```dart
class MyGoRouterBridge implements GoRouterLike {
  MyGoRouterBridge(this._router);
  final GoRouter _router; // from package:go_router

  @override
  String get location => _router.routerDelegate.currentConfiguration.uri.toString();

  @override
  List<String> get knownRoutes => const ['orders', 'order_detail', 'checkout'];

  @override
  List<String> get stack => /* derive from router state */ const [];

  @override
  List<String> get tabs => const [];

  @override
  Map<String, dynamic>? get params => /* path/query params */ null;

  @override
  void go(String location, {Object? extra}) => _router.go(location, extra: extra);

  @override
  void pop() => _router.pop();

  @override
  bool canPop() => _router.canPop();
}
```

Or supply a custom `NavigationAdapter`:

```dart
NavigationAdapter(
  getState: () => RuntimeNavState(
    screenId: 'orders',
    stack: const ['orders'],
  ),
  getKnownRoutes: () => const ['orders', 'checkout'],
  navigate: (screenId, [params]) async { /* router.go(...) */ },
  back: () async { /* router.pop() */ },
);
```

## Session binding

- Prefer a backend-minted `sessionId` (chat session, auth session, booking id, etc.).
- Pass the **same** id to `Xecutioner.init` / `createUiClient` and to `createOpenAiAgent` / `createVercelAiUiTools`.
- Do not rely on client auto-generated `xec_*` ids unless the backend observes `listOnlineSessions()` / `onSessionConnected` before binding tools.
- Commands for another session are never delivered to this client.

## Lifecycle

| Call                           | When                                                                |
| ------------------------------ | ------------------------------------------------------------------- |
| `client.connect()`             | After hooks are ready (typically after first frame / router mount)  |
| `client.isConnected()`         | Gate UI that depends on AI control                                  |
| `client.disconnect()`          | On logout, dispose, or background if you do not want remote control |
| `client.executeLocal(command)` | Tests / demos without a live server                                 |

## Local demo (no server)

```bash
cd examples/flutter-chat-demo
dart pub get
dart run bin/run_demo.dart
dart test
```

This exercises context → navigate → input → tap via `executeLocal` against a mock host tree.

## Package tests

```bash
cd packages/flutter
dart pub get
dart test
```

## What not to put in the Flutter client

- Model API keys
- Agent planning / chat UI
- Business logic that belongs on your server

Backend owns tools, policy, and session routing. See [backend.md](./backend.md).
