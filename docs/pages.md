---
type: Reference
title: BastionUI Screens
description: Screens, routes, and the providers/widgets each one wires together.
doc_id: pages
layer: [surface]
project: bastion-ui
status: active
keywords: [screens, routes, riverpod, navigation, dashboard, sessions, briefing]
related: [capabilities, architecture, api-reference]
---

# BastionUI Screens

## What this page is for

You are changing a screen, or trying to find which file draws the thing you are looking
at, and need the provider/widget/route wiring behind each one. For *what the app can do
and how to invoke it*, read [`capabilities.md`](capabilities.md) instead — this page
assumes you already know what the screen is for.

All screens live in [`lib/screens/`](../lib/screens/). Routing is handled by
`BastionApp.onGenerateRoute` in [`lib/main.dart`](../lib/main.dart); the app's root shell
(`HomeShell` → `_ConnectedBody`) hosts a bottom `NavigationBar` with five tabs
(**Briefing · Sessions · Dashboard · Actions · Runs**), and Settings is pushed from the
app bar rather than being a tab.

## `HomeShell` (`lib/main.dart`)

Not itself routed — the app's home widget. Owns the `BastionSocket`/`BastionApi`
lifecycle (open on startup, reconnect on config change, dispose on teardown) and
renders `ConnectionBanner` above either a "Configure a connection" placeholder or
`_ConnectedBody`.

### `_ConnectedBody` (private, `lib/main.dart`)

Rendered once the socket/API are live. `IndexedStack` of five tabs so all stay mounted:

| Tab | Screen | Icon |
|---|---|---|
| 0 | `BriefingScreen` | `Icons.today_outlined` |
| 1 | `SessionsListScreen` | `Icons.list` |
| 2 | `DashboardScreen` | `Icons.dashboard` |
| 3 | `QuickActionsScreen` | `Icons.flash_on` |
| 4 | `RunsScreen` | `Icons.play_circle_outline` |

Also activates `notificationWiringProvider` and
`workflowDoneNotificationWiringProvider`, and shows a foreground `SnackBar` on
`workflow_done` events (`'$repo — $specSlug is $status'`).

## `SettingsScreen`

Not tab-routed — pushed via the AppBar settings `IconButton` on `HomeShell`. Four fields:

| Field | Notes |
|---|---|
| Server host | Tailscale IP or hostname of the `bastion serve` machine |
| Port | Default `4317` — `bastion serve`'s compiled-in `--addr` default, per `bastion/docs/serve-api.md`. Confirm the port your server is actually bound to |
| Bearer token | Validated with host/port, then saved via `ConnectionNotifier.saveConfig` (persists through `FlutterSecureStorage`) |
| Engine API key *(optional)* | Saved via `ConnectionNotifier.saveEngineKey`; an **empty value is a valid save** meaning "no engine access" (it deletes the stored key rather than erroring) |

Saving the engine key immediately re-runs `EngineApi.probeMount()` and renders the result
as a status pill under the field — `checking…` / `not configured` / `engine not mounted on
this server` / `key rejected` / `connected`. The five states are kept distinct on purpose:
"no key" and "wrong key" and "server has no engine" are different problems with different
fixes.

> **Deployment note:** the Mac Mini's real console instance (`com.brandon.bastion-serve`) is
> bound to port `8080`, not `4317` — see `docs/infrastructure.md`'s Services table. `4317`
> remains correct as the app's default for now (local dev/testing on this machine); revisit
> before shipping to a phone that needs to reach the Mini for real.

## `BriefingScreen`

Tab 0. The app's first-run landing screen — an operator "what needs me right now" digest.
Watches `briefingViewModelProvider` (`state/briefing_provider.dart`), which composes three
independently-fetching sections: `GET /api/board` (`?graph=true`, paid on every load),
`GET /api/attention`, and the existing `sessionsProvider`. Each section can load, error, or
succeed independently — a failed section renders its own inline error + retry without
blocking the other two.

- **Header** (`BriefingHeader`) — three `StatTile`s in consequence order: needs-you (operator
  gates + needs-input sessions), blocked (blocked-lane attention carryover), running (live
  sessions). A section error renders that stat as an em dash rather than a stale/zero count.
- **Lane 1 — gates** (`BriefingGatesLane`) — `GateCard`s for board blocks blocked on an
  operator/approval dependency, ranked by blast radius (`dependent_count`, nulls sort last);
  `GateCard.onAct` navigates to the existing `/repos/<name>` route. Needs-input sessions render
  as `SeverityRow`s with an `AgeChip` derived from `now.subtract(idle)`.
- **Lane 2 — blocked blocks** — `AttentionCarryoverDto` entries in the `blocking` lane, ranked
  by `age_days` descending, rendered as `SeverityRow`s with a "waiting on" phrase from
  `unmetBlocks`.
- **Lane 3 — live runs** — sessions with `state == 'running'` and a non-blocked agent state,
  sorted by name, rendered as `SeverityRow`s.

Each lane has its own namespaced error/empty state (`briefing-lane-error-<laneId>` /
`briefing-lane-empty-<laneId>`) and its own retry action wired to
`refreshFailedBriefingSections`. The `GateCard` "Act" button and lane retry buttons are scoped
to `AppTokens.accent2` via a local theme override (distinguished from the accent2 active/RUNNING
`StatusPill` by a filled-vs-bordered structural channel, not hue).

See `lib/state/briefing_model.dart` for the pure ranking/view-model layer (`BriefingViewModel`,
`BriefingSectionState<T>`) and `test/e2e/briefing_e2e_test.dart` for the real-server e2e
cross-check.

## `SessionsListScreen`

Tab 1. Watches `sessionsProvider` (live session list) and `needsInputProvider` (flagged
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

Tab 2. Watches `briefingBoardProvider` (`?graph=true`, root-scope — the same board
fetch the Briefing tab uses) and runs it through `rankPortfolio()`
(`lib/state/portfolio_ranking.dart`), which groups every repo into one of three
Eyebrow-headed tiers — **Needs attention** / **Active** / **Quiet** — ranked by
blocked-block count, open gates, and staleness. Each repo renders as a `SeverityRow`
with a trailing `LaneBar` (done/now/blocked/next counts), a `StatusPill` (tone fixed
per D4 constraint 3 — active reads louder than idle), an `AgeChip` derived from the
repo's newest block `lastTouched` (or a "not started" chip when every block is
never-worked), and a `Sparkline` of the last 7 days of block activity (omitted when the
repo had no activity in that window). The Quiet tier collapses to a single
tap-to-expand summary row (first 3 names + "+N more") by default, regardless of entry
count. `now` is captured once in `initState`, never reread from the wall clock.
Tapping a row navigates to `/repos/<name>` via `repoDetailRouteName(name)`.

## `RepoDetailScreen`

Route: `/repos/<name>` (route argument: `repoName`). Watches two providers.

From `repoBoardProvider(repoName)` (`state/repo_board_provider.dart`, BU.13.C) — the
repo's **typed** block records from `GET /api/board`:

- `RepoDetailStats` — three `StatTile`s counting the now/next/blocked *lanes*.
- `RepoDetailBlockLanes` — one group per lane, each block a `SeverityRow` with a
  readiness pill (`READY` / `WAITING` / `UNKNOWN`; anything in the blocked lane always
  reads `BLOCKED`) and a "what it waits on" phrase from
  `state/blocked_by_label.dart`. Every lane renders a **named** empty state
  ("nothing blocked", etc.) — never a gap, and never a literal `[]` (that was a shipped
  bug, `BU.ticket.dashboard-now-render`, guarded by `repo_detail_empty_test.dart`).

These deliberately read the typed lane lists, never `RepoStatusDto`'s prose
`now`/`next`/`blocked` strings — the two can disagree, and that disagreement is why the
typed path exists.

From `repoWorkflowsProvider(repoName)` — the same family the dashboard row watches:

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

Tab 3. Watches `commandsProvider` (persisted, user-editable command-palette list),
rendering one tile per `PaletteCommand` with edit/delete `IconButton`s and tap-to-invoke
on the tile itself; a FAB opens a shared add/edit `AlertDialog` (label + command
fields). Tapping a tile opens `CommandInvokeSheet` (inject/spawn mode toggle, session
picker for inject, name/dir/model fields for spawn); on success it calls
`BastionApi.postCommand` and navigates to `/sessions/<name>` using the
server-returned session id. `ApiError`/`FatalAuthError` are surfaced inline in the sheet
without navigating.

## `RunsScreen` (BU.13.E)

Tab 4. Watches `runsProvider` (`state/runs_provider.dart`) — REST-seeded via
`BastionApi.getRuns()` then kept live over the bearer-authed `"runs"` WS topic,
applying `run_transition` events (a `terminal: true` transition removes the run; every
other status, including `suspended`, upserts it in place). Renders one row per
`RunSummaryDto` with a status badge (`_RunStatusVisual`: a `StatusTones` tone plus a
distinct icon per wire status, not colour alone) and an `AgeChip`.

The list header also carries a launch entry point (`BU.12.E` task 5) next to the
`Eyebrow` — a small text-icon control (`TextButton.icon`, not a `FilledButton`,
so it reads as secondary to the run rows), backed by its own lazily-constructed
`EngineApi` + mount probe (`_RunsScreenState._initLaunchEngine`, same pattern as
`_RunDetailBodyState`). Disabled with a distinguishable visible reason per
`EngineStatus` cause (no key / not mounted / unauthorized / unreachable / checking)
rather than hidden. Tapping it opens `LaunchSheet` (`lib/screens/launch_sheet.dart`,
task 4) via `showLaunchSheet`; the runs list is already WS-live, so a successful
launch's new run appears without a manual refetch.

Tapping a row drills in (internal screen state, not a pushed route) to that run's
`GET /api/runs/{id}` node list, rendering each `NodeTransitionDto` as a vertical row —
a DAG view is out of scope for this block. `GET /api/runs` returning `200 []` (no
engine mounted) renders a real explanatory empty state, never an error or an endless
spinner. `suspended` renders in the same live `active` tone as `running` (with a pause
icon instead of a play icon) so it never reads as finished alongside the settled
`success`/`failed`/`cancelled`/`budget_halted` tones.

See `lib/screens/runs_screen.dart`'s doc comment and `test/e2e/runs_ws_e2e_test.dart`
for the real-server e2e cross-check (asserts the empty-state path honestly — the dev
harness here has no engine mounted, so the live-update half of the flow isn't
exercised e2e).

## `LaunchSheet` (`BU.12.E`, `lib/screens/launch_sheet.dart`)

Modal bottom sheet opened via `showLaunchSheet(context, {required EngineApi engine})`,
which resolves the new run id on a successful (`202`) launch or `null` on any
dismissal. Takes an already-constructed, already-probed `EngineApi` from its caller
(mirrors `_RunDetailBodyState`'s pattern) rather than building its own — the caller
owns the engine's lifecycle.

Form fields: repo, workflow type (populated live from `engineWorkflowsProvider`'s
registry, never hardcoded), and spec slug; one primary Launch action. Server-side
`422` responses render as field-level errors (`InputDecoration.errorText`) for
`repo`/`spec slug`/`workflow type`; `LaunchPolicyFailed`, `LaunchUnresolvableTargetRoot`,
and any unrecognised `422` render as a sheet-level banner since they name no single
field. On `LaunchAccepted`, the sheet invalidates `runsProvider` to force a fresh REST
reseed so the new run appears immediately, then pops the route with the new run id.

## Route table (`BastionApp.onGenerateRoute`)

| Prefix | Screen | Helper |
|---|---|---|
| `/sessions/<name>` | `SessionDetailScreen` | `sessionDetailRouteName(name)` in `sessions_list_screen.dart` |
| `/repos/<name>` | `RepoDetailScreen` | `repoDetailRouteName(name)` in `dashboard_screen.dart` |
