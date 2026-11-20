# Flutter chat demo (scripted)

End-to-end style demo for `xecutioner_flutter` using a mock host UI tree — no device and no model API key.

```bash
cd examples/flutter-chat-demo
dart pub get
dart run bin/run_demo.dart
dart test
```

For the full WebSocket + `@xecutioner/server` path, use `examples/rn-chat-demo` against the same protocol; this package validates the Dart client API surface locally via `executeLocal`.
