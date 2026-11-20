# Xecutioner Protocol v0.1

Canonical schemas live in `packages/protocol/schemas/protocol.json`.

## Handshake

Client → server:

- `type: "handshake"`
- `protocolVersion: "0.1.0"`
- `sessionId`
- `capabilities[]`
- optional `clientInfo`

Server replies with the same shape and negotiated capabilities.

## Snapshot

- `snapshotId`, optional `screen` / `route`, `capturedAt`, `elements[]`
- Element: `id`, `role`, optional `label`, `value`, `state`, `bounds`, `actions`, `children`, `redacted`
- Addressing: developer stable IDs (`testID`) first; generated `ref_*` fallbacks

## Commands

Each command includes `callId`, `action`, `idempotencyKey`, `deadline`, and action-specific fields.

Actions: `tap`, `scroll`, `input`, `read_screen`, `wait_for`, `get_context`, `navigate`, `back`.

Navigate uses `screenId` + optional `params`. Results may include `appContext`.

## App context

Combines three sources on the client:

1. Runtime observation (current screen, stack, tabs, params)
2. Declared screen map (`defineScreens`)
3. Auto-extracted route names from the navigation adapter

## Results

- `ok: true` with optional post-action `snapshot` and/or `appContext`
- `ok: false` with `errorCode`:
  `stale_snapshot` | `element_not_found` | `not_actionable` | `blocked_by_policy` | `timeout` | `client_unavailable` | `invalid_arguments` | `internal_error` | `unknown_screen` | `navigation_unavailable`

## Transport (MVP)

WebSocket messages: `handshake`, `command`, `result`, `ping`, `pong`, `client_unavailable`.
