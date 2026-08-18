---
type: TestArtifact
title: Visual Smoke Run — 2026-08-18 16:19 local
description: Manual release-build capture of BastionUI after the Phase 12 engine-control chain (BU.12.A/B/D/E), including the Settings engine-key panel, the launch sheet, and a real pre-flight 422.
doc_id: visual-smoke-2026-08-18-161940
layer: [surface]
project: bastion-ui
status: active
keywords: [patrol, visual-smoke, screenshots, phase-12, engine-control, release-build]
related: [context, status]
---

# Visual Smoke Run — 2026-08-18 16:19 local

First capture after the Phase 12 engine-control chain (`BU.12.A`, `BU.12.B`, `BU.12.D`, `BU.12.E`).
Diff target: `runs/2026-08-15_133215`.

**This is the first run of this convention driven against a `--release` build**, and that choice is
the reason it found the INTERNET-permission defect below. Every prior visual-smoke and Patrol run
used debug builds.

## Environment

- Device: Android emulator `Pixel_9` (`emulator-5554`), 1080x2424
- App: `flutter run --release`, `app-release.apk` (20.6MB), commit `4d8cc0f` + the manifest fix
- Backend: `bastion serve` on `127.0.0.1:4317`, reached from the emulator as `10.0.2.2:4317`,
  bearer token `patrol-smoke-token`
- Engine: **mounted** — `DATABASE_URL` + `BASTION_ENGINE_API_KEY` present, `GET /workflows`
  returns 10 registered types
- Data: the real live HQ corpus (28 need-you, 4 blocked, 15 repos needing attention)

## Screens captured

| # | File | What it shows |
|---|---|---|
| 01 | `01_cold_start.png` | Launch screen, brand gem |
| 02 | `02_home_briefing.png` | Unconfigured empty state + disconnected banner |
| 03 | `03_settings_empty.png` | **`BU.12.A`** — the new ENGINE panel, `NOT CONFIGURED` probe pill |
| 04 | `04_settings_filled.png` | Both secrets masked (Standing Rule 7, visually confirmed) |
| 05 | `05_settings_saved_engine_probe.png` | `Settings saved` + probe pill in its danger state |
| 06 | `06_home_after_connect.png` | **The INTERNET-permission defect** — `SocketException ... errno = 1` |
| 07 | `07_briefing_live_release_fixed.png` | After the fix: Connected, live Briefing, real gate cards |
| 08 | `08_runs_list_launch_entry.png` | **`BU.12.E`** — Launch entry point, secondary weight; designed empty state |
| 09 | `09_launch_sheet.png` | **`BU.12.E`** — three inputs, one primary action |
| 10 | `10_launch_workflow_registry.png` | All 10 live registry types, not hardcoded |
| 11 | `11_launch_filled.png` | `SDLC_FLOW` + a deliberately bogus repo |
| 12 | `12_launch_422_unknown_repo.png` | **The pre-flight 422 on a real device** — names the slug, lists every valid one |
| 13 | `13_runs_after_trigger.png` | Runs list still empty after 6 concurrent triggers (see findings) |
| 14 | `14_sessions.png` | Sessions list |
| 15 | `15_dashboard_portfolio.png` | **`BU.13.D`** — lane bars, gate pills, age chips, sparklines |
| 16 | `16_actions.png` | Quick actions |

## What was verified working

- The Engine panel is on-brand: a third `PanelCard` with an `Eyebrow`, an obscured field with the
  same eye-toggle affordance as the bearer token, and a `StatusPill` carrying the probe result.
- The probe's distinct outcomes render distinctly — `NOT CONFIGURED` (neutral) and
  `SERVER UNREACHABLE` (danger) were both observed. This is the payoff of modelling the probe as
  five outcomes rather than a bool.
- The launch sheet holds its scope: three inputs, one primary action, no profile selector, no
  policy panel, no request preview.
- The workflow dropdown matches `GET /workflows` exactly (10 types, sorted).
- **The `SDLC_FLOW` pre-flight 422 surfaces the server's message verbatim on a real device**,
  naming `no-such-repo` and enumerating all 24 known slugs, with the sheet staying open and its
  values intact for correction.

## What could NOT be verified, and why

**The run detail screen and `BU.12.D`'s pause/resume/abort control row were never reachable.**
Every registered workflow type on this server completes in roughly 2ms, so `GET /api/runs` returns
`[]` even when six runs are triggered concurrently one second earlier (capture 13). This is the
same root cause that forced `BU.12.D`'s e2e to be respecced (decision D-7), and this run upgrades
it from a test-harness limitation to a **product-verification** one: the control row cannot be seen
by a human either. It needs a deliberately slow fixture workflow registered in the engine.
