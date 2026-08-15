# Visual smoke run — 2026-08-15 13:32 (post-Phase-13, engine mounted)

## Why this run

First capture after the Phase 13 chain (`BU.11.A`, `ticket-integration-test-tier`, `BU.13.A`–`BU.13.E`).
**First run ever against a server with the engine actually mounted**, which is what makes the Runs
screen and the live-update path testable at all.

## Environment

- **Device:** `emulator-5554` (AVD `Pixel_9`), Android emulator
- **App build:** `flutter build apk --debug -t lib/main.dart` (explicit entrypoint — a leftover Patrol
  bundle APK hangs on the splash screen waiting for an instrumentation server)
- **Package:** `com.bastionui.bastion_ui` (note: NOT `com.example.bastion_ui`)
- **Backend:** `core/bastion/target/release/bastion serve --addr 0.0.0.0:4317 --token patrol-smoke-token`
- **Engine:** **MOUNTED** — server log: `engine routes mounted (DATABASE_URL + engine_api_key present)`.
  Env sourced from `core/bastion/.env`. `GET /workflows` returns 10 registered workflow types.
- **Connectivity:** `adb reverse tcp:4317 tcp:4317`; app configured to `127.0.0.1:4317`
- **Data:** the real HQ corpus (server started from `agentic-portfolio/`, so `/api/board` resolves the
  real `brain.toml` rather than a fixture)
- **App state:** `adb shell pm clear` first — a genuine cold first-run

## Screens

| # | Screen | What it shows |
|---|---|---|
| 01 | Launch, unconfigured | Cold start: Disconnected banner on the ground ladder, "Configure a connection in Settings" |
| 02 | Settings, empty | Connection + Authentication panels, port pre-filled 4317 |
| 03 | Settings, filled | host `127.0.0.1`, token masked (18 chars) |
| 04 | Settings saved | "Settings saved" — **stock light Material snackbar, off-brand** (see findings) |
| 05 | **Briefing (new, tab 0)** | 29 need-you / 8 blocked / 1 running; real `GateCard`s with real blast radius ("3 BLOCKS GATED") from `dependent_count` via `?graph=true`; `Act` in accent2 |
| 06 | **Portfolio (rebuilt)** | `NEEDS ATTENTION · 15` tier; `LaneBar` + key per repo; `AgeChip` 1d/8d/2d; `business` = **"not started"** (the never-worked-vs-stale distinction working); sparklines |
| 07 | **Runs (new)** | Honest empty state: "No live runs — Nothing is running right now, or this server has no engine mounted." |
| 08 | Sessions | Two real tmux sessions (`Core`, `orchestration`) with agent-state dots |
| 09 | Actions | Quick-action command palette |

## Verified working end-to-end

- Cold start → configure → connect → real data, no manual intervention beyond typing the host/token.
- Five tabs fit at phone width; the new Briefing and Runs tabs are both reachable.
- `?graph=true` enrichment reaches the UI: gate blast-radius counts are real.
- The never-worked-vs-stale distinction renders as "not started", not a fabricated age.

## Findings (see planning/orchestration-run/.../notes.md)

- **The "Settings saved" snackbar is stock light Material** — white ground, dark text, in a dark-only
  app. `AppTheme.dark` binds no `SnackBarThemeData`.
- **Two accent hues still compete, now visibly within one screen:** the selected nav label is
  `primary` #5D7BFF while `Act` buttons are `accent2` #58B6FF. `BU.13.F` owns the reconciliation.
- **`StatusTones.success` resolves to `accent3` (purple), not the green `AppTokens.runDone`** — so the
  `LaneBar`'s "done" segment reads purple while a green "done" token sits defined and unused.
- **15 of ~16 repos land in *needs attention*** — the tier is nearly everything, so it discriminates
  little. Either the thresholds want tuning or the corpus really is that blocked.
- Sessions/Actions are untouched by Phase 13 and still show the sparse pre-instrument layout.

## NOT verified here

**The live-update path** — a run starting elsewhere and appearing on the phone untouched. The engine
is mounted and the registry is reachable, but no run was launched: every registered workflow does real
work (`SDLC_FLOW` starts a coding pipeline; `LEAD_INGEST`/`OPPORTUNITY_*` mutate business records), so
firing one is an operator decision, not an agent one.
