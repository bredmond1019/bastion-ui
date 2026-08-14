---
type: Reference
title: BastionUI Screens
description: Screens, routes, and the providers/widgets each one wires together.
doc_id: pages
layer: [surface]
project: bastion-ui
status: active
keywords: [screens, routes, riverpod, navigation, dashboard, sessions]
related: [architecture, api-reference]
---

# BastionUI Screens

All screens live in `lib/screens/`. Routing is handled by `BastionApp.onGenerateRoute`
in `lib/main.dart`; the app's root shell (`HomeShell` → `_ConnectedBody`) hosts a
bottom `NavigationBar` with three tabs.

## `HomeShell` (`lib/main.dart`)

Not itself routed — the app's home widget. Owns the `BastionSocket`/`BastionApi`
lifecycle (open on startup, reconnect on config change, dispose on teardown) and
renders `ConnectionBanner` above either a "Configure a connection" placeholder or
`_ConnectedBody`.

### `_ConnectedBody` (private, `lib/main.dart`)

Rendered once the socket/API are live. `IndexedStack` of three tabs so all stay mounted:

| Tab | Screen | Icon |
|---|---|---|
| 0 | `SessionsListScreen` | `Icons.list` |
| 1 | `DashboardScreen` | `Icons.dashboard` |
| 2 | `QuickActionsScreen` | `Icons.flash_on` |

Also activates `notificationWiringProvider` and
`workflowDoneNotificationWiringProvider`, and shows a foreground `SnackBar` on
`workflow_done` events (`'$repo — $specSlug is $status'`).

## `SettingsScreen`

Not tab-routed — pushed via the AppBar settings `IconButton` on `HomeShell`. Form for
server host, port (default `4317` — matches `bastion serve`'s compiled-in `--addr` default,
per `bastion/docs/serve-api.md`), and bearer token; validates all three, then calls
`ConnectionNotifier.saveConfig` (persists via `FlutterSecureStorage`).

> **Deployment note:** the Mac Mini's real console instance (`com.brandon.bastion-serve`) is
> bound to port `8080`, not `4317` — see `docs/infrastructure.md`'s Services table. `4317`
> remains correct as the app's default for now (local dev/testing on this machine); revisit
> before shipping to a phone that needs to reach the Mini for real.

## `SessionsListScreen`

Tab 0. Watches `sessionsProvider` (live session list) and `needsInputProvider` (flagged
session names), rendering one `SessionCard` per session (sorted by name). Below the
`ResponsiveScaffold` tablet breakpoint (720dp), tapping a card navigates to
`/sessions/<name>` via `sessionDetailRouteName(name)`, unchanged. At/above the
breakpoint (`ResponsiveScaffold.isWide`), tapping a card instead sets
`selectedSessionProvider` and the screen renders the list and an inline
`SessionDetailScreen(embedded: true)` for the selected session side by side via
`ResponsiveScaffold` (BU.4.A).

## `SessionDetailScreen`

Route: `/sessions/<name>` (route argument: `sessionName`). Watches
`paneProvider(sessionName)` for the live pane buffer, rendering `PaneView` +
`ApproveButtonRow` + a free-text send bar (`_SendBar`, sends literal keys via
`BastionApi.sendKeys` on submit). Takes an `embedded` flag (default `false`); when
`true` (rendered inline as `SessionsListScreen`'s tablet detail pane rather than pushed
as its own route) the AppBar's implied back button is suppressed (BU.4.A).

## `DashboardScreen`

Tab 1. Watches `reposProvider` (workspace-registry repo list, sorted by name).
Each row (`_RepoRow`) additionally watches `repoWorkflowsProvider(repo.name)` to derive
a `StatusBadge` — `RepoBadgeState.inFlight` if any workflow has `status == 'running'`,
else `RepoBadgeState.hasHandoff` if `repo.hasHandoff`, else `RepoBadgeState.idle`.
Pull-to-refresh (`RefreshIndicator`) calls `reposProvider`'s `RepoListNotifier.refresh`.
Tapping a row navigates to `/repos/<name>` via `repoDetailRouteName(name)`.

## `RepoDetailScreen`

Route: `/repos/<name>` (route argument: `repoName`). Watches the same
`repoWorkflowsProvider(repoName)` family as the dashboard row for:

- `_StatusTable` — the parsed `now`/`next`/`blocked` + five momentum fields as a
  label/value list (blank values omitted).
- `_HandoffSection` (only mounted when `status.hasHandoff`) — watches a screen-local
  `repoHandoffProvider(repoName)` `FutureProvider` (`GET /api/repos/{name}/handoff`)
  and renders `info.title` + `MarkdownView(info.body)`; a resolved `null` or fetch
  error both render nothing.
- One `WorkflowProgress` row per `WorkflowStateDto` in `workflowsState.workflows`
  (`spec_slug`, `task <n> — <status>`, `branch:` as plain text).

Both `DashboardScreen`/`_RepoRow` and `RepoDetailScreen` react live to `workflow_done`
WS events for the matching repo — `repoWorkflowsProvider` auto-refetches, so badges and
the workflow list update without a manual refresh.

## `QuickActionsScreen`

Tab 2. Watches `commandsProvider` (persisted, user-editable command-palette list),
rendering one tile per `PaletteCommand` with edit/delete `IconButton`s and tap-to-invoke
on the tile itself; a FAB opens a shared add/edit `AlertDialog` (label + command
fields). Tapping a tile opens `CommandInvokeSheet` (inject/spawn mode toggle, session
picker for inject, name/dir/model fields for spawn); on success it calls
`BastionApi.postCommand` and navigates to `/sessions/<name>` using the
server-returned session id. `ApiError`/`FatalAuthError` are surfaced inline in the sheet
without navigating.

## Route table (`BastionApp.onGenerateRoute`)

| Prefix | Screen | Helper |
|---|---|---|
| `/sessions/<name>` | `SessionDetailScreen` | `sessionDetailRouteName(name)` in `sessions_list_screen.dart` |
| `/repos/<name>` | `RepoDetailScreen` | `repoDetailRouteName(name)` in `dashboard_screen.dart` |
