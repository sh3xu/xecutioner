# RN chat demo

End-to-end demo of `@xecutioner/server` + thin client hooks completing a multi-screen task **without** a model API key.

```bash
pnpm --filter @xecutioner/rn-chat-demo start
```

Flow: list → order detail → checkout (email + submit), driven by a scripted agent calling `ui_*` tools over WebSocket.

See `src/integration.snippet.tsx` for the ~10-line React Native bridge pattern.
