# xecutioner_flutter

Thin Flutter / Dart client for Xecutioner in-app UI control.

Mirrors `@xecutioner/react-native`: WebSocket handshake, snapshot serialization, command executors, and navigation context.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  xecutioner_flutter:
    path: ../path/to/flutter # or git repository
```

---

## Quickstart (Universal Functional Pattern)

No UI widget wrapping needed. You register your actions in pure Dart functions using `ExecutionerActions`:

```dart
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

// 1. Define your action registry
final actions = ExecutionerActions();

// Register button taps (connect to controllers, ViewModels, or Blocs)
actions.onTap(
  'login-button',
  label: 'Sign in',
  onTap: () => authController.signIn(),
);

// Register text fields
actions.onInput(
  'email-input',
  label: 'Email',
  getValue: () => emailController.text,
  setValue: (text) => emailController.text = text,
);

// Register switches / checkboxes
actions.onTap(
  'remember-me-switch',
  role: 'switch',
  label: 'Remember me',
  checkedGetter: () => rememberMe.value,
  onTap: () => rememberMe.toggle(),
);

// 2. Initialize Xecutioner
final xecutioner = await Xecutioner.init(
  XecutionerConfig(
    url: 'ws://your-backend-host:4100/xecutioner',
    sessionId: 'my-session-id',
    app: const AppInfo(name: 'Shop', description: 'Shopping app'),
    navigation: createGoRouterAdapter(
      CreateGoRouterAdapterOptions(getRouter: () => router),
    ),
    screens: const [
      ScreenDefinition(id: '/home', title: 'Home'),
      ScreenDefinition(id: '/orders', title: 'Orders'),
    ],
    actions: actions,
  ),
);
```

---

## Supported Navigation Systems

- **GoRouter**: `createGoRouterAdapter(...)`
- **Navigator 1.0 (Named Routes)**: `createNavigatorAdapter(...)` with `ExecutionerNavigatorObserver`
- **GetX**: `createGetXAdapter(...)`
- **Custom Routers**: Pass `NavigationAdapter(getState: ..., navigate: ..., back: ...)`

---

## Running Tests

```bash
flutter test
```
