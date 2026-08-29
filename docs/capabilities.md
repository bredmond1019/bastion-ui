---
type: Reference
title: BastionUI Capability Catalogue
description: Everything BastionUI can do, one line each, with how to invoke it in the app and the client method behind it.
doc_id: capabilities
layer: [surface]
project: bastion-ui
status: active
keywords: [capabilities, catalogue, actions, screens, routes, engine]
related: [pages, api-reference, architecture]
---

# BastionUI Capability Catalogue

Every operator-facing thing this app can do, what to tap to do it, and the client
method behind it. Derived from `lib/` (screens, `BastionApi`, `EngineApi`) — not from
the docs index, so a capability that exists in code but has no screen still appears
here, in [Not surfaced in the UI](#not-surfaced-in-the-ui-yet).

## What this page is for

You are looking at a phone or tablet and want to know what it can actually *do* — or
you are an agent that needs the list of app capabilities without reading 68 Dart
files. Screen-by-screen internals (which provider backs which widget) live in
[`pages.md`](pages.md); the client's full method/route surface lives in
[`api-reference.md`](api-reference.md).

## Quickstart

```bash
flutter pub get
flutter run -d <device-id>
```

Then tap the **gear icon** in the app bar and fill in host, port and token — nothing
else in this catalogue works until that is saved. Host/port/token values and how to
install onto a real device: [`device-install.md`](device-install.md).

Five bottom-navigation tabs, in order: **Briefing · Sessions · Dashboard · Actions ·
Runs**. Settings is pushed from the app bar, not a tab.

## Connect and configure

| Capability | How to invoke it | Behind it |
|---|---|---|
| Point the app at a `bastion serve` instance | Settings → Server host, Port, Bearer token → **Save** | `ConnectionNotifier.saveConfig`, token in `flutter_secure_storage` |
| Enable the workflow engine (optional) | Settings → **Engine API key (optional)** → Save | `EngineApi`, `X-API-Key` auth |
| See whether the engine is actually reachable | Settings — the status pill under the engine key field | `EngineApi.probeMount()` — five distinct states: checking / not configured / not mounted / key rejected / connected |
| See connection state at any time | The banner above every screen; tap it to open Settings | `BastionSocket.statusStream` |

An empty engine key is a valid save meaning "no engine access" — the engine tabs then
show a *reason*, never a hidden control.

## Triage what needs you — Briefing tab

| Capability | How to invoke it | Behind it |
|---|---|---|
| See the three counts that matter (needs-you / blocked / running) | Briefing, header | `GET /api/board?graph=true` + `GET /api/attention` + live sessions |
| Work the operator gates, worst blast radius first | Briefing → gates lane → **Act** (jumps to that repo) | Board blocks whose `blocked_by` is an operator/approval dep, ranked on `dependent_count` |
| See blocked work ranked by how long it has been stuck | Briefing → blocked lane | `AttentionCarryoverDto` entries in the `blocking` lane, ranked on `age_days` |
| Retry just the part that failed | Briefing → the inline error on that lane → retry | `refreshFailedBriefingSections` — each of the three sections loads, errors and retries independently |

## Drive an agent session — Sessions tab

| Capability | How to invoke it | Behind it |
|---|---|---|
| See every live session, with its agent state and a needs-input flag | Sessions tab | `GET /api/sessions`, then the live `sessions` WS topic |
| Watch a session's terminal pane live | Tap a session (tablet: it opens beside the list) | `GET /api/sessions/{name}/pane`, then the `pane:<name>` WS topic |
| Answer a waiting prompt in one tap | Session detail → the **y / Enter / Esc / 1 / 2** row | `BastionApi.sendKeys` (literal, `Enter` appended server-side) and `sendKey` (symbolic tmux keys) |
| Type anything into a session | Session detail → the send bar at the bottom | `POST /api/sessions/{name}/send` |
| Get told when a session needs you while the app is backgrounded | Nothing — it is automatic once connected | Local notification on the `needs_input` event |

## Watch the portfolio — Dashboard tab

| Capability | How to invoke it | Behind it |
|---|---|---|
| See every repo tiered **Needs attention / Active / Quiet** | Dashboard tab | `rankPortfolio()` over the same board fetch the Briefing uses |
| Judge a repo at a glance — lane counts, how stale, last 7 days of activity | Dashboard, each row: `LaneBar`, `AgeChip`, `Sparkline` | Per-block `last_touched` from the board (a repo with no activity in the window renders no sparkline, never a fake flat line) |
| Collapse the noise | Dashboard → the Quiet tier is one summary row; tap to expand | — |
| See a repo's real block records, lane by lane, with why each is blocked | Tap a repo row | `GET /api/board` scoped to that repo — typed records, not the prose summary; each block shows `READY` / `WAITING` / `BLOCKED` / `UNKNOWN` |
| Read a repo's `status.md` — now / next / blocked + the five momentum fields | Repo detail, Status panel | `GET /api/repos/{name}/status` |
| Read a repo's `handoff.md` rendered as markdown | Repo detail, when the repo has one | `GET /api/repos/{name}/handoff` |
| See that repo's in-flight and finished SDLC workflows | Repo detail, bottom | `GET /api/repos/{name}/workflows`; auto-refetches on a `workflow_done` event |

## Fire a command — Actions tab

| Capability | How to invoke it | Behind it |
|---|---|---|
| Keep your own command palette | Actions tab → FAB to add, per-tile icons to edit/delete | `commandsProvider`, persisted under `bastion.commands.list` |
| Inject a command into a running session | Tap a tile → **inject** → pick the session → Send | `POST /api/actions/command`, `mode: inject` |
| Spawn a new session running a command | Tap a tile → **spawn** → name, optional dir, optional model (`opus`/`sonnet`) | `POST /api/actions/command`, `mode: spawn`; navigates to the new session |

## Run workflows — Runs tab

Everything in this section needs the engine mount configured (see
[Connect and configure](#connect-and-configure)). Without it the tab shows an
explanatory empty state and the launch control is **disabled with a visible reason**,
never hidden.

| Capability | How to invoke it | Behind it |
|---|---|---|
| See every live and recent run, with status and age | Runs tab | `GET /api/runs`, then the bearer-authed `runs` WS topic |
| Launch a workflow run | Runs tab → the launch control beside the header → repo, workflow type, spec slug → **Launch** | `POST /events/`; the workflow-type picker is populated live from the server's registry, never hardcoded |
| Inspect a run's nodes — status, timings, token usage, errors | Tap a run row | `GET /api/runs/{id}` (a list, not a DAG view) |
| Pause a run | Run detail → **Pause** | `POST /events/{id}/pause` |
| Resume a paused run | Run detail → **Resume** | `POST /events/{id}/resume` |
| **Abort a run** — not reversible | Run detail → **Abort** → confirm in the sheet naming the run id | `POST /events/{id}/abort`. This is the one destructive control in the app, and it is the only one behind a confirmation sheet |
| Get told when an SDLC workflow finishes | Automatic — a notification, plus a foreground snackbar | `workflow_done` event, keyed per `repo:spec_slug` |

## Not surfaced in the UI yet

These exist and are tested in the client but no screen calls them. They are real
capabilities of `bastion serve` that BastionUI can already speak — listed so nobody
rebuilds the client half, and so a reader does not assume the UI covers the API.

| Client method | Route | What it would give you |
|---|---|---|
| `BastionApi.getLanes({epic})` | `GET /api/lanes` | Fleet-wide lane-segment availability — per segment, whether it is startable or held (and why), plus how many lanes closing it would free. No screen renders this. |
| `BastionApi.getDocsTree` / `getDocsFile` | `GET /api/docs/{repo}/tree`, `.../file` | Browsing and reading a repo's allowlisted markdown from the phone |
| `BastionApi.createSession` / `deleteSession` | `POST /api/sessions`, `DELETE /api/sessions/{name}` | Creating/killing a session directly; today sessions are only ever spawned via the Actions tab's command path |
| `EngineApi.listSuspended()` | `GET /events/suspended` | A "what is paused right now" list |
| `EngineApi.getWorkflowGraph(type)` | `GET /workflows/{type}/graph` | The DAG behind a workflow type — the raw JSON has no DTO and no view |
| `EngineApi.getEvent(runId)` | `GET /events/{id}` | The raw event payload for a run |

`BastionApi.getHealth()` (`GET /health`) is a liveness probe used by tooling and the
dev-environment script, not an operator capability.

## See also

- [`pages.md`](pages.md) — each screen's providers, widgets and routes.
- [`api-reference.md`](api-reference.md) — every client method, DTO and WS frame.
- [`architecture.md`](architecture.md) — how a fact gets from the server to a widget.
- [`device-install.md`](device-install.md) — getting this onto a real device.
