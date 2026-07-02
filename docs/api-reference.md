---
type: Reference
title: BastionUI API Client Reference
description: BastionApi REST methods and BastionSocket WS frames consumed by BastionUI.
doc_id: api-reference
layer: [surface]
project: bastion-ui
status: active
keywords: [rest, websocket, bastion-api, bastion-socket, dto, serve-api]
related: [architecture]
---

# BastionUI API Client Reference

BastionUI mirrors (never defines) the `bastion serve` HTTP+WS contract owned by
`bastion/docs/serve-api.md` in the `bastion` repo. This doc describes BastionUI's own
client-layer surface — `lib/services/bastion_api.dart` (REST) and
`lib/services/bastion_socket.dart` (WebSocket) — not the server contract itself.

## `BastionApi` (`lib/services/bastion_api.dart`)

REST client for `http://<host>:<port>`. Every request sends `Authorization: Bearer
<token>` and `Accept: application/json`. A `401` response always throws
`FatalAuthError` (caller must not retry); any other non-2xx throws `ApiError`.

| Method | Route | Returns | Notes |
|---|---|---|---|
| `getHealth()` | `GET /health` | `HealthDto` | Public route; header sent anyway |
| `getSessions()` | `GET /api/sessions` | `List<SessionDto>` | |
| `getPane(name, {lines})` | `GET /api/sessions/{name}/pane` | `PaneDto` | `lines` caps trailing lines returned |
| `sendKeys(name, keys)` | `POST /api/sessions/{name}/send` | `void` | Literal keys, followed by `Enter` server-side |
| `sendKey(name, key)` | `POST /api/sessions/{name}/key` | `void` | Symbolic tmux key name (e.g. `Escape`) |
| `createSession(name, {dir})` | `POST /api/sessions` | `void` | 201 on success |
| `deleteSession(name)` | `DELETE /api/sessions/{name}` | `void` | 204 on success |
| `getRepos()` | `GET /api/repos` | `List<RepoSummaryDto>` | Workspace-registry repo list |
| `getRepoStatus(name)` | `GET /api/repos/{name}/status` | `RepoStatusDto` | Parsed `status.md` |
| `getRepoHandoff(name)` | `GET /api/repos/{name}/handoff` | `HandoffInfo?` | Returns `null` (not a throw) on 404 with `code == 'C002'` (no handoff.md); any other 404 body/code still throws `ApiError` |
| `getRepoWorkflows(name)` | `GET /api/repos/{name}/workflows` | `List<WorkflowStateDto>` | In-flight + completed SDLC workflows for the repo |

`dispose()` releases the underlying `IoHttpTransport`'s socket connections.

### DTOs (`lib/models/`)

- `HealthDto`, `ErrorPayload` — `models/dto.dart`
- `SessionDto`, `PaneDto` — `models/session_dto.dart`
- `RepoSummaryDto { name, now, hasHandoff }` — one dashboard row
- `RepoStatusDto { name, now, next, blocked, hasHandoff, momentumNow, momentumNext, momentumBlocked, momentumImprove, momentumRecurring }` — parsed `status.md`
- `HandoffInfo { title, body }` — parsed `handoff.md`
- `WorkflowStateDto { specSlug, branch, status, currentTask, startedAt, updatedAt }` — one SDLC workflow; `currentTask` is a JSON integer (`num?.toInt()`), not a string, per serve-api.md v0.3 §11.3 verified directly against the source contract. No PR-link field exists on this DTO.

All DTOs live in pure-Dart files (no Flutter imports) with `fromJson`/`toJson` and are
unit-tested for round-trip decoding in `test/models/`.

## `BastionSocket` (`lib/services/bastion_socket.dart`)

Manages `ws://<host>:<port>/ws` with capped exponential backoff reconnect (1s, 2s, 4s,
8s, 16s, 32s cap) via `computeBackoff(attempt)`. Exposes:

- `statusStream` — `Stream<ConnectionStatus>` (`disconnected` / `connecting` /
  `connected` / `reconnecting`), delivered synchronously.
- `frames` — `Stream<BastionFrame>`, decoded via `BastionFrame.fromJson`.
- `isFatalAuth` — `true` after a 401/unauthorized/forbidden error on the handshake or
  in-stream; reconnect stops permanently (construct a new instance to retry).
- `send(Map<String, dynamic> json)` — no-op unless `status == connected`.
- `connect()` / `dispose()` — lifecycle; the instance cannot be reused after `dispose()`.

### `BastionFrame` kinds (`lib/models/frame.dart`)

| Kind | Class | Fields |
|---|---|---|
| `echo` | `EchoFrame` | `payload` |
| `error` | `ErrorFrame` | `payload: ErrorPayloadFrame { code, message }` |
| `sessions` | `SessionsFrame` | `sessions: List<SessionDto>` |
| `pane` | `PaneFrame` | `session, seq, lines` |
| `event` | `EventFrame` | `session, event, extra` (raw payload map) |
| *(unrecognised)* | `UnknownFrame` | `kind, payload` — forward-compatible, never throws |
| *(decode failure)* | `MalformedFrame` | `raw, reason` |

### Client → server frame encoders (`ClientFrames`)

- `subscribe(topic)` / `unsubscribe(topic)` — topics: `"sessions"`, `"pane:<name>"`.
- `send({session, keys})` — literal key sequence.
- `sendKey({session, key})` — single symbolic key.

### Known `EventFrame.event` values

- `needs_input` (`state/events_provider.dart`'s `needsInputEvent`) — a session is
  blocked waiting for operator input; `session` carries the session name.
- `workflow_done` (`state/workflows_provider.dart`'s `workflowDoneEvent`) — an SDLC
  workflow for a repo finished; repo-scoped events carry `session: ""` and the repo
  name / spec slug / status live in `extra['repo']` / `extra['spec_slug']` /
  `extra['status']`.
