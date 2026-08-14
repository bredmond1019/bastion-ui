---
type: TestArtifact
title: Visual Smoke Run — 2026-08-14 16:48 UTC-3 (brand header lockup + banner ground)
description: Post-lockup visual capture of every BastionUI screen driven against real bastion serve — supersedes 2026-08-14_155931 as the exit artifact for operator gate G1 (bastion-ui-brand-signoff).
doc_id: visual-smoke-2026-08-14-164803
layer: [surface]
project: bastion-ui
status: active
keywords: [visual-smoke, screenshots, brand-signoff, bastiel-lockup, connection-banner, android-emulator]
related: [context, visual-smoke-2026-08-14-155931]
---

# Visual Smoke Run — 2026-08-14 16:48 (brand header lockup + banner ground)

**This run supersedes `2026-08-14_155931` as the exit artifact for operator gate G1
(`bastion-ui-brand-signoff`), which gates `BU.11.B`.** That capture was taken before
`BU.ticket.brand-header-lockup` landed, so it shows the plain-text "BastionUI" app bar and the
saturated connection banner. Reviewing it would mean signing off on a superseded state.

**The gate itself is NOT closed by this run.** Captured and stopped — the sign-off is the operator's.

## Environment

- **Device:** Android emulator `Pixel_9` (`emulator-5554`), 1080×2424 @ 420dpi — same device as both
  prior baselines, so the three runs are directly comparable.
- **App build:** `flutter build apk --debug -t lib/main.dart`, unsigned debug build, rebuilt
  explicitly with the `lib/main.dart` entrypoint per the F6 trap now documented in
  `visual_smoke/README.md`.
- **Backend:** real `bastion serve --addr 0.0.0.0:4317 --token patrol-smoke-token`, reached from the
  emulator at `10.0.2.2:4317`. Binary: `~/.cargo/bin/bastion`, **rebuilt 2026-08-14 15:14** by the
  `bastion` lane's `chore-okf-core-type-adaptation`. This is the first capture in this repo served
  by a binary that is not stale — the previous two ran against the 2026-08-13 build.
- **Data:** live, not fixtures — the operator's real repo registry and real tmux sessions
  (`Core`, `orchestration`).
- **Captured by:** the orchestration session directly, via `adb exec-out screencap`, after the
  `/sdlc-task` run's own task 4 could not (its sandbox had no `adb`/emulator access and it correctly
  declined to fabricate a run rather than inventing one).

## What changed since `2026-08-14_155931`

| # | Change | Where it shows |
|---|---|---|
| 1 | **The bastiel lockup replaces the plain-text "BastionUI" app-bar title** — gem icon (32dp) + wordmark (22dp), 10dp gap | every screen with the `HomeShell` app bar: `01`, `04`, `05`, `07`, `08`, `09`, `10` |
| 2 | **`ConnectionBanner` no longer inverts the ground ladder** — it was filling the full bar with a tone's `foreground`; it now sits on `tone.background` with a `tone.border` hairline | `01` (disconnected/red), `05`–`10` (connected/blue) |
| 3 | **The lockup moved from `ResponsiveScaffold` to `HomeShell`** after this capture's first pass showed it was not rendering at all — see below | `05` (one app bar, one lockup, no stacking) |

### The defect this capture caught

The first pass of `BU.ticket.brand-header-lockup` put the lockup in `ResponsiveScaffold`. Every gate
passed — 442 tests green, `flutter analyze` clean — and the app bar still read "BastionUI", because
`ResponsiveScaffold` is used as a `body:`: on a phone its `AppBar` would render *below* `HomeShell`'s
real one, and on Dashboard/Actions (which do not use it) the lockup did not render at all.

This is the same failure mode as `BU.1.A` — built, but not on the path that renders — now hit twice
in this repo. Fixed by moving the lockup into `HomeShell`'s `AppBar` and removing the redundant
`ResponsiveScaffold` copies, with `test/widgets/home_shell_lockup_test.dart` added to pin it to the
*rendering* path specifically rather than merely asserting the widget exists somewhere.

## Screens

| File | Screen | What to look at |
|---|---|---|
| `01_launch_unconfigured.png` | Home, no connection configured | Lockup in the app bar; disconnected banner now a dark tinted ground with a hairline, not a red slab |
| `02_settings_empty.png` | Connection settings, empty | Token field on `surfaceMuted`, `line` borders |
| `03_settings_filled.png` | Settings with host/port/token entered | Token masked; no literal colours |
| `04_settings_saved.png` | Settings after save | — |
| `05_home_connected.png` | Sessions tab, connected | **One app bar, one lockup, no stacking** — the fix verified. `SESSIONS` eyebrow, session cards as `PanelCard` + `GradientTopBar` with alternating hues |
| `06_session_detail.png` | Session detail (`Core`) | Pushed route: back arrow + session name, deliberately no lockup. `TERMINAL`/`QUICK APPROVE` eyebrows, pane on `AppTokens.paper` with mono type, `Esc` destructive-toned |
| `07_dashboard.png` | Dashboard | The clearest before/after against `155931`: same screen, banner now subordinate. `HeadingRule` under "Repositories", repo cards as `PanelCard` + `IconTile` + `StatusPill` (`IDLE`/`HANDOFF`/`IN FLIGHT`), no literal `[]` |
| `08_repo_detail.png` | Repo detail | — |
| `09_quick_actions_empty.png` | Actions, command palette | `Command Palette` heading + rule, command cards with `IconTile`, destructive-toned delete icons |
| `10_quick_actions_add_dialog.png` | Actions, add-command dialog | Dialog on `AppTokens.surface` |

## Honest ceilings

- **Tablet (≥720dp) was not captured.** The `ResponsiveScaffold` split view only renders above the
  breakpoint and this emulator is a phone profile. The lockup's tablet behaviour is covered by
  widget tests (`test/widgets/responsive_test.dart`), not by a screenshot — so "reads correctly on a
  tablet" remains unverified visually.
- **No `StatusPill` appears on the session cards** in `05` because both live sessions were idle at
  capture time; the agent-state affordance is exercised by widget tests and the Patrol step, not
  here.
- **This is a debug build**, hence the DEBUG ribbon in the top-right of every capture. It is not a
  brand defect.
