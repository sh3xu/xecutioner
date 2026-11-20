# xecutioner_flutter

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**`xecutioner_flutter`** is a high-performance, framework-agnostic client SDK for AI in-app UI control. It connects your Flutter app to an AI agent over WebSockets, captures semantic UI snapshots, and executes user actions (tapping, text typing, scrolling, and navigation) dispatched by the AI model.

---

## Key Features

- **Zero Widget Tree Intrusion**: No need to wrap widgets with special UI wrappers. Register actions cleanly in standard Dart functions.
- **Universal Router Support**: Built-in adapters for **GoRouter**, **GetX**, standard Flutter **`Navigator 1.0`**, or any custom routing system.
- **Robust Auto-Reconnection**: Exponential backoff on network dropouts and immediate reconnect when returning from background (`AppLifecycleState.resumed`).
- **Comprehensive Logging**: Structured logging of all incoming events, parameters, action executions, results, and network transitions.
- **Declarative Safety Policy**: Client-side wildcard rules (`*`, `?`) to allow, deny, redact, or require interactive user confirmation for sensitive/destructive actions.
- **Zero-Network Unit Testing**: Built-in `executeLocal` allows complete testing of AI flows without a running backend or WebSocket server.

---

## Architecture Overview

```
┌─────────────────────────────────┐           WebSocket            ┌───────────────────────────────┐
│         Backend AI Agent        │ ◄────────────────────────────► │        Flutter Host App       │
│  (LLM + @xecutioner/server)     │       JSON Wire Protocol       │      (xecutioner_flutter)     │
└─────────────────────────────────┘                                └──────────────┬────────────────┘
                                                                                  │
                                                      ┌───────────────────────────┴───────────────────────────┐
                                                      ▼                                                       ▼
                                            ┌───────────────────┐                                   ┌───────────────────┐
                                            │ NavigationAdapter │                                   │ExecutionerActions │
                                            │(GoRouter/GetX/Nav)│                                   │(onTap / onInput)  │
                                            └───────────────────┘                                   └───────────────────┘
```

---

## Step-by-Step Integration Guide

### Step 1: Install Dependency

Add `xecutioner_flutter` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xecutioner_flutter:
    path: ../path/to/flutter # or git repository: git@github.com:your-org/xecutioner_flutter.git
```

Run:
```bash
flutter pub get
```

---

### Step 2: Choose Your Navigation Adapter

The SDK needs to know what screen the app is currently on, and how to navigate between screens.

#### Option A: GoRouter
```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final navigationAdapter = createGoRouterAdapter(
  CreateGoRouterAdapterOptions(getRouter: () => myGoRouter),
);
```

#### Option B: GetX
```dart
import 'package:get/get.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final navigationAdapter = createGetXAdapter(
  CreateGetXAdapterOptions(
    currentRoute: () => Get.currentRoute,
    toNamed: (route, {arguments}) async => Get.toNamed(route, arguments: arguments),
    back: () async => Get.back(),
    knownRoutes: () => ['/home', '/search', '/profile', '/settings'],
  ),
);
```

#### Option C: Standard Flutter Navigator 1.0 (Named Routes)
Attach `ExecutionerNavigatorObserver` to your `MaterialApp.navigatorObservers`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final navigatorObserver = ExecutionerNavigatorObserver();

MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [navigatorObserver],
  routes: myRoutes,
);

final navigationAdapter = createNavigatorAdapter(
  CreateNavigatorAdapterOptions(
    navigatorKey: navigatorKey,
    observer: navigatorObserver,
  ),
);
```

---

### Step 3: Declare Your Screen Catalog

Declare the screens the AI is allowed to understand and navigate between:

```dart
const List<ScreenDefinition> appScreens = [
  ScreenDefinition(
    id: '/home',
    title: 'Home',
    description: 'Dashboard displaying recent activity and quick actions',
  ),
  ScreenDefinition(
    id: '/search',
    title: 'Search',
    description: 'Search catalog with filters for category and location',
    params: {'query': 'string'},
  ),
  ScreenDefinition(
    id: '/profile',
    title: 'User Profile',
    description: 'View user info, settings, and orders',
  ),
  ScreenDefinition(
    id: '/payment',
    title: 'Checkout & Payment',
    description: 'Submit order payment',
    params: {'orderId': 'string'},
    policy: 'approval', // Requires confirmation before navigating
  ),
];
```

---

### Step 4: Register Interactive Elements (`ExecutionerActions`)

Define an `ExecutionerActions` instance and register your buttons, inputs, and toggles:

```dart
final actions = ExecutionerActions();

void registerAppActions(ExecutionerActions actions) {
  // ── Text Inputs ──────────────────────────────────────────────────────────
  actions.onInput(
    'search-input-field',
    label: 'Search query',
    visibleGetter: () => isScreen('/search'),
    getValue: () => searchController.text,
    setValue: (String text) => searchController.text = text,
  );

  // ── Sensitive / Password Inputs (auto-redacted in snapshots) ─────────────
  actions.onInput(
    'login-password-field',
    label: 'Password',
    sensitive: true, // Redacts value in AI snapshots
    visibleGetter: () => isScreen('/login'),
    getValue: () => passwordController.text,
    setValue: (String text) => passwordController.text = text,
  );

  // ── Button Taps ──────────────────────────────────────────────────────────
  actions.onTap(
    'search-submit-button',
    label: 'Search',
    visibleGetter: () => isScreen('/search'),
    onTap: () => searchController.performSearch(),
  );

  // ── Checkboxes & Switches ────────────────────────────────────────────────
  actions.onTap(
    'terms-agreement-checkbox',
    role: 'checkbox',
    label: 'I accept terms & conditions',
    visibleGetter: () => isScreen('/signup'),
    checkedGetter: () => termsAccepted.value,
    onTap: () => termsAccepted.toggle(),
  );

  // ── Scrollable Lists ─────────────────────────────────────────────────────
  actions.onScroll(
    'feed-list-view',
    label: 'Activity feed',
    onScroll: ({direction, amount}) async {
      if (direction == 'down') {
        feedScrollController.animateTo(
          feedScrollController.offset + (amount ?? 300),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    },
  );
}
```

---

### Step 5: Configure Safety & Security Policies (`XecutionerPolicy`)

Prevent the AI from executing dangerous actions without user confirmation:

```dart
const policy = XecutionerPolicy(
  // Wildcards supported: * (any characters), ? (single character)
  approvalElementPatterns: [
    'payment-confirm-button',
    'delete-account-button',
    'transfer-funds-*',
  ],
  denyElementPatterns: [
    'root-admin-*',
  ],
  redactElementPatterns: [
    '*-card-cvv',
    '*-ssn',
  ],
  approvalScreens: [
    '/payment',
  ],
);
```

---

### Step 6: Initialize Xecutioner

Initialize in your bootstrap or `main.dart` after the router is mounted:

```dart
final xecutioner = await Xecutioner.init(
  XecutionerConfig(
    url: 'ws://10.0.2.2:4100/xecutioner', // Use your server address
    sessionId: 'session-user-123',         // Must match backend tool binding
    app: const AppInfo(
      name: 'ShopApp',
      description: 'E-commerce mobile app for browsing and purchasing goods.',
    ),
    navigation: navigationAdapter,
    screens: appScreens,
    actions: actions,
    policy: policy,

    // Automatic reconnection settings:
    autoReconnect: true,
    initialReconnectDelay: const Duration(seconds: 1),
    maxReconnectDelay: const Duration(seconds: 30),

    // Confirm sensitive actions:
    onApprovalRequest: (ApprovalRequest request) async {
      return await showDialog<bool>(
        context: navigatorKey.currentContext!,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm AI Action'),
          content: Text('Allow the AI assistant to perform "${request.elementId ?? request.action}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Deny')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
          ],
        ),
      ) ?? false;
    },

    // AI acting indicator:
    onAiActing: (bool acting) {
      debugPrint('AI is currently executing an action: $acting');
    },
  ),
);
```

---

## Observability & Logging

The SDK provides structured, real-time logging across all subsystems.

### 1. Log Stream (`xecutioner.logs`)
Listen to `xecutioner.logs` to display live logs in your UI or debug consoles:

```dart
xecutioner.logs.listen((String logMessage) {
  debugPrint(logMessage);
});
```

#### Log Categories:
- **`[WS]`**: WebSocket lifecycle (connecting, handshake, ping/pong, disconnects, reconnect timers).
- **`[CMD]`**: Incoming AI commands, target element/screen, call IDs, and parameters.
- **`[ACTION]`**: Action dispatch, element matching, controller updates, and fallback handling.
- **`[POLICY]`**: Allowed, denied, or approval-prompted decisions.

### 2. Connection Status Stream (`xecutioner.connectionStatus`)
```dart
xecutioner.connectionStatus.listen((bool isConnected) {
  print('Network status: ${isConnected ? "Online" : "Reconnecting..."}');
});
```

### 3. AI Acting Stream (`xecutioner.acting`)
```dart
xecutioner.acting.listen((bool isActing) {
  // Update banner or button glowing state
});
```

---

## Offline Unit Testing (`executeLocal`)

Test your AI actions and screen transitions without any WebSocket or backend server:

```dart
test('AI fills out sign up form', () async {
  final actions = ExecutionerActions();
  final nameController = TextEditingController();

  actions.onInput(
    'name-input',
    label: 'Name',
    getValue: () => nameController.text,
    setValue: (t) => nameController.text = t,
  );

  final xecutioner = await Xecutioner.init(
    XecutionerConfig(
      connectOnInit: false, // Pure offline mode
      actions: actions,
    ),
  );

  // Directly execute action command locally
  final result = await xecutioner.input('name-input', 'Jane Doe');

  expect(result.ok, isTrue);
  expect(nameController.text, 'Jane Doe');
});
```

---

## Wire Protocol Commands Reference

The SDK handles all official wire protocol actions dispatched by the backend:

| Action | Description | Key Parameters |
| :--- | :--- | :--- |
| `read_screen` | Captures and serializes the visible UI hierarchy | `snapshotId` (optional freshness check) |
| `get_context` | Returns current screen info and list of reachable screens | `maxDestinations` |
| `navigate` | Moves to a declared screen | `screenId`, `params` |
| `back` | Pops the top screen from the navigation stack | *none* |
| `tap` | Dispatches tap handler on a registered element | `elementId` |
| `input` | Enters text into an input element | `elementId`, `text` |
| `scroll` | Scrolls a registered scrollable element | `elementId`, `direction`, `amount` |
| `wait_for` | Polls until an element or label appears on screen | `elementId`, `labelContains`, `timeoutMs` |

---

## License

MIT © Xecutioner
