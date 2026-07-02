---
type: Reference
title: BastionUI Architecture
description: Module map, key types, and data flow for the BastionUI Flutter app.
doc_id: architecture
layer: [surface]
project: bastion-ui
status: active
keywords: [flutter, riverpod, websocket, rest, dto, providers]
related: [api-reference, pages]
---

# BastionUI Architecture

BastionUI is a thin Flutter client over `bastion serve`'s HTTP+WebSocket API (contract
owned by the `bastion` repo's `bastion/docs/serve-api.md`; never edited here — see
CLAUDE.md Standing Rule 6). It talks only to the Tailscale tailnet, never shells out to
git/tmux, and stores the bearer token via `flutter_secure_storage`.

## Directory map

```
lib/
├── main.dart               ← app entry, HomeShell (socket/API lifecycle), routing, tab bar
├── models/                 ← pure-Dart DTOs + frame (de)serialization (no Flutter imports)
│   ├── dto.dart             — HealthDto, ErrorPayload
│   ├── frame.dart           — BastionFrame sealed hierarchy (WS envelope)
│   ├── session_dto.dart     — SessionDto, PaneDto
│   └── repo_status_dto.dart — RepoSummaryDto, RepoStatusDto, HandoffInfo, WorkflowStateDto
├── services/                ← transport layer
│   ├── bastion_api.dart     — REST client (BastionApi)
│   ├── bastion_socket.dart  — WebSocket client with reconnect (BastionSocket)
│   └── notifications.dart   — local-notification wrapper + riverpod wiring
├── state/                   ← riverpod providers
│   ├── connection_provider.dart — server config + live ConnectionStatus
│   ├── sessions_provider.dart   — live session list + bastionSocketProvider/bastionApiProvider injection points
│   ├── pane_provider.dart       — per-session live pane buffer
│   ├── events_provider.dart     — needs_input event stream + flag set
│   ├── repos_provider.dart      — workspace-registry repo list
│   └── workflows_provider.dart  — per-repo status/workflows + workflow_done event stream
├── screens/                 ← full-page widgets
│   ├── settings_screen.dart
│   ├── sessions_list_screen.dart
│   ├── session_detail_screen.dart
│   ├── dashboard_screen.dart
│   └── repo_detail_screen.dart
└── widgets/                 ← presentational, mostly provider-free components
    ├── connection_banner.dart
    ├── session_card.dart
    ├── pane_view.dart
    ├── approve_button_row.dart
    ├── status_badge.dart
    ├── markdown_view.dart
    └── workflow_progress.dart
```

## Data flow

### Connection lifecycle

`main.dart`'s `HomeShell` owns the `BastionSocket`/`BastionApi` instances:

1. On first frame, reads persisted `ConnectionConfig` + bearer token
   (`state/connection_provider.dart`, backed by `FlutterSecureStorage`) and opens the
   socket (no-op if host is unconfigured).
2. Publishes the live socket/API instances onto the shared root-scope injection points
   `bastionSocketProvider` / `bastionApiProvider` (`state/sessions_provider.dart`) —
   plain `StateProvider<T?>`s, `null` until set, so screens pushed via the app's
   `Navigator` (an ancestor of `HomeShell`) still see the same live instances.
3. Bridges `BastionSocket.statusStream` into `connectionProvider` so `ConnectionBanner`
   and other widgets update in real time.
4. Watches `connectionProvider` for config changes (e.g. after `SettingsScreen` saves)
   and reconnects automatically.

Once both providers are non-null, `HomeShell` renders `_ConnectedBody`, a bottom
`NavigationBar` with two tabs (`SessionsListScreen`, `DashboardScreen`) inside an
`IndexedStack` (both screens stay mounted so provider state survives tab switches).
`_ConnectedBody` also activates `notificationWiringProvider` and
`workflowDoneNotificationWiringProvider` (local-notification bridges) and shows a
foreground `SnackBar` on `workflow_done` events.

### REST + WS seed/live pattern

Most list-shaped state (`sessionsProvider`, `paneProvider`, `reposProvider`,
`repoWorkflowsProvider`) follows the same pattern: seed via a one-shot REST call, then
either subscribe to a WS topic for live updates (sessions, pane) or re-fetch on a
matching WS `event` frame (repo workflows — there is no WS push for the repo list
itself). A boolean guard (e.g. `_sawWsSnapshot`) ensures a slower REST response never
overwrites state a faster WS frame already updated.

### Routing

`BastionApp.onGenerateRoute` handles two dynamic route prefixes:
- `/sessions/<name>` → `SessionDetailScreen` (pushed from `SessionCard.onTap` via
  `sessionDetailRouteName()` in `sessions_list_screen.dart`)
- `/repos/<name>` → `RepoDetailScreen` (pushed from `_RepoRow.onTap` via
  `repoDetailRouteName()` in `dashboard_screen.dart`)

## Key types

- `BastionFrame` (`models/frame.dart`) — sealed class decoding the WS envelope
  `{"kind": ..., "payload": ...}` into `EchoFrame`, `ErrorFrame`, `SessionsFrame`,
  `PaneFrame`, `EventFrame`, `UnknownFrame` (unrecognised `kind`, forward-compatible),
  or `MalformedFrame` (decode failure). Never throws.
- `RepoSummaryDto` / `RepoStatusDto` / `HandoffInfo` / `WorkflowStateDto`
  (`models/repo_status_dto.dart`) — mirror serve-api.md v0.3 §11's repo/workflow REST
  surface. `WorkflowStateDto.currentTask` is a JSON integer (verified directly against
  serve-api.md rather than trusting the task spec's prose summary, which implied a
  string).
- `RepoWorkflowsState` (`state/workflows_provider.dart`) — `{status, workflows,
  loading}` snapshot for one repo, held by `RepoWorkflowsNotifier`.
- `RepoBadgeState` (`widgets/status_badge.dart`) — `idle` / `inFlight` / `hasHandoff`,
  in that priority order (in-flight outranks a pending handoff).

## Dashboard + repo-detail flow (BU.2.A)

- `DashboardScreen` watches `reposProvider` for the repo list (sorted by name) and, per
  row, `repoWorkflowsProvider(repo.name)` to derive a `RepoBadgeState` — in-flight
  workflow (`status == 'running'`) outranks a pending handoff, which outranks idle.
  Pull-to-refresh calls `RepoListNotifier.refresh()`.
- `RepoDetailScreen` watches the same `repoWorkflowsProvider(repoName)` family for the
  parsed `RepoStatusDto` (rendered as a label/value table via `_StatusTable`) and the
  `WorkflowStateDto` list (one `WorkflowProgress` row each). When
  `status.hasHandoff` is true it also watches a screen-local
  `repoHandoffProvider` (`FutureProvider.family<HandoffInfo?, String>`) that calls
  `GET /api/repos/{name}/handoff` directly — a resolved `null` or fetch error both
  render nothing (`SizedBox.shrink()`), matching "omit without error".
- `repoWorkflowsProvider` auto-refetches whenever a `workflow_done` `EventFrame` with
  `extra['repo'] == repoName` arrives (via the shared `workflowDoneEventsProvider`),
  which is what flips the dashboard badge and repo-detail workflow list live, without a
  manual refresh.
- `workflowDoneNotificationWiringProvider` (`services/notifications.dart`) mirrors the
  existing needs-input notification bridge as a second, independent channel keyed by
  `'$repo:$specSlug'.hashCode` so distinct specs for the same repo don't collide.

## Known contract gap

`WorkflowStateDto` has no PR-link field on the current serve-api contract —
`widgets/workflow_progress.dart` renders `branch` as plain text only, never a link. See
`planning/2.A-dashboard-repo-detail/tasks.md` for the tracked gap.
