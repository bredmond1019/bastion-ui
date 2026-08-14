---
type: TestArtifact
title: Visual Smoke Run — 2026-08-14 15:59 UTC-3 (post-brand)
description: Post-re-skin visual capture of every BastionUI screen driven against real bastion serve — the exit artifact for operator gate G1 (bastion-ui-brand-signoff).
doc_id: visual-smoke-2026-08-14-155931
layer: [surface]
project: bastion-ui
status: active
keywords: [patrol, visual-smoke, screenshots, brand-signoff, android-emulator, re-skin]
related: [context, visual-smoke-2026-08-14-061003]
---

# Visual Smoke Run — 2026-08-14 15:59 (post-brand)

Second capture of this convention — the post-re-skin baseline, diffed against the pre-brand
baseline `visual_smoke/runs/2026-08-14_061003/`. This is the exit artifact for operator gate
`bastion-ui-brand-signoff` (G1), which gates `BU.11.B`. **Captured and stopped here — the gate
itself is not closed by this task; that is the operator's call.**

## Environment

- Device: Android emulator `Pixel_9` (`emulator-5554`), Android SDK 37 (API level reported by
  `ro.build.version.sdk`), physical resolution 1080x2424 @ 420dpi — same device as the pre-brand
  baseline.
- App build: `flutter build apk --debug -t lib/main.dart`, unsigned debug build. (Note: the
  `app-debug.apk` left over from Task 8's Patrol run had `patrol_test/test_bundle.dart` as its
  entrypoint, not `lib/main.dart` — it hung on the splash screen waiting for a Patrol
  instrumentation server that wasn't attached. Rebuilt explicitly with `-t lib/main.dart` before
  capturing.)
- Backend: real `bastion serve --addr 0.0.0.0:4317 --token patrol-smoke-token`, the prebuilt
  `~/.cargo/bin/bastion` binary (built 2026-08-14 15:14, version `0.1.0`) — per the block's
  environment fact 2, no fresh binary can currently be built (`okf-core → mev → bastion` chain is
  red), and this binary is adequate here because the capture is about the app's own pixels, not
  server correctness. Run locally on the host, reachable from the emulator via `10.0.2.2`.
  `DATABASE_URL` unset, so Engine routes were not mounted this boot (same as the pre-brand
  baseline).
- bastion-ui commit: `137e90e` (branch `10.C-reskin-screens-icon-flow`, tasks 1-8 of this spec
  already committed on top of it).
- Data fixtures: 2 real tmux sessions (`Core`, `orchestration`), the real local repo workspace
  registry (23 repos, same registry as the pre-brand baseline).

## How this was captured

Driven via `adb shell input tap/text` + `adb exec-out screencap -p`, coordinates read from
`adb shell uiautomator dump` bounds (not eyeballed). Same manual process as the pre-brand
baseline — still not scripted.

## Screens captured

| File | Screen | Notes |
|---|---|---|
| `01_launch_unconfigured.png` | Home, no connection configured | Dark `AppTokens.paper` ground, orange `StatusPill`-style disconnected banner replaces the old green/red Material banner |
| `02_settings_empty.png` | Settings, first open | `PanelCard` sections with mono/uppercase `Eyebrow` labels (`CONNECTION`, `AUTHENTICATION`); port pre-filled `4317` |
| `03_settings_filled.png` | Settings, host+token entered | Focused-field treatment now token-derived (blue focus ring on `surfaceMuted` ground) |
| `04_settings_saved.png` | Settings, "Settings saved" snackbar | — |
| `05_home_connected.png` | Sessions tab, connected | 2 real tmux sessions rendered as `PanelCard` + `GradientTopBar` (hue cycled by index); "Connected" banner is now a solid brand-blue bar, not stock Material green |
| `06_session_detail.png` | Session detail (`Core`) | Terminal pane keeps `AppTokens.paper` ground with mono type; quick-key chips (`y`/`Enter`/`Esc`/`1`/`2`) re-skinned onto token outline buttons |
| `07_dashboard.png` | Dashboard tab | Real repo registry; each repo card is `PanelCard`+`GradientTopBar`+`IconTile`, status now `StatusPill` text (`IDLE`/`HANDOFF`/`IN FLIGHT`) instead of the pre-brand literal `[]` + bare Material icon |
| `08_repo_detail.png` | Repo detail (`amistad`) | Real now/next/blocked/momentum from its `status.md`; empty `now` renders "nothing in flight" prose, never a literal `[]` — `BU.ticket.dashboard-now-render` fix confirmed still intact post-re-skin |
| `09_quick_actions_empty.png` | Actions tab | Not empty — 4 real persisted commands, each `PanelCard`+`GradientTopBar`+`IconTile` (lightning glyph) |
| `10_quick_actions_add_dialog.png` | Actions, add-command dialog | Dialog surface on `AppTokens.surface`, `Cancel`/`Save` as brand-blue text actions |

## Comparison against pre-brand baseline (`2026-08-14_061003`)

Every one of the 10 screens changed visibly. The pre-brand baseline was stock Flutter Material
light theme throughout (`#F5F7FA`-ish light grounds, black text, default `Card` elevation,
Material green/red status banners, bare `ListTile` rows). The post-brand capture replaces all of
that with the dark `AppTokens` palette, `PanelCard`/`GradientTopBar`/`IconTile`/`StatusPill`/
`Eyebrow` primitives, and mono/uppercase treatment confined to labels. Concretely:

- **Dashboard (07)**: pre-brand showed a literal `[]` under each repo name (the un-fixed
  `now`/`blocked` render) and a plain grey dot / orange-exclamation-triangle Material icon for
  status. Post-brand shows no `[]` anywhere and `StatusPill` text badges (`IDLE`, `HANDOFF`,
  `IN FLIGHT`).
- **Sessions (05)**: pre-brand used a stock light `ListTile` list under a green "Connected"
  banner. Post-brand uses `PanelCard`+`GradientTopBar` cards under a solid brand-blue banner.
- **Settings (02-04)**: pre-brand had plain Material `TextField`s on a white ground. Post-brand
  has `PanelCard` sections, mono/uppercase `Eyebrow` group labels, and token-coloured focus rings.
- No screen in this run shows a raw white/light Material surface, a default `Card` shadow, or an
  un-styled `ListTile` — confirms the acceptance criterion "no stock Material surface remains" for
  all 10 captured screens. (This is a visual read over the PNGs on disk, standing in for the
  un-gateable criterion per D64 — the gated proof is `test/screens/brand_coverage_test.dart` from
  Task 6.)
