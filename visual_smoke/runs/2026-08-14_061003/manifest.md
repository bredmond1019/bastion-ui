---
type: TestArtifact
title: Visual Smoke Run — 2026-08-14 06:10 UTC
description: Manifest for the first Patrol visual-smoke capture — baseline screenshots of every BastionUI screen driven against real bastion serve.
doc_id: visual-smoke-2026-08-14-061003
layer: [surface]
project: bastion-ui
status: active
keywords: [patrol, visual-smoke, screenshots, baseline, android-emulator]
related: [context]
---

# Visual Smoke Run — 2026-08-14 06:10 UTC

Baseline run. First capture of this convention — nothing to diff against yet.

## Environment

- Device: Android emulator `Pixel_9` (`emulator-5554`), Android SDK 36.1, physical
  resolution 1080x2424 @ 420dpi
- App build: `flutter build apk --debug`, unsigned debug build
- Backend: real `bastion serve --addr 0.0.0.0:4317 --token patrol-smoke-token`,
  run locally on the host machine, reachable from the emulator via `10.0.2.2`
  (no mocks — `DATABASE_URL` unset, so Engine routes were not mounted this boot)
- bastion-ui commit: `c5a5e5a` (working tree dirty — Patrol spike not yet committed:
  `pubspec.yaml`/`pubspec.lock`, `android/app/build.gradle.kts`,
  `android/app/src/androidTest/`, `patrol_test/`)
- bastion commit: `eda10b3`
- Data fixtures: 3 real tmux sessions (`Core`, `orchestration`, `patrol-smoke-demo`
  — the last created for this run, killed after capture), the real local repo
  workspace registry (23 repos)

## How this was captured

Driven manually via `adb shell input tap/text` + `adb exec-out screencap -p`,
coordinates read from `adb shell uiautomator dump` bounds (not eyeballed —
Flutter's rendered pixel space doesn't match the tool's downscaled image
preview). Not scripted yet — see `visual_smoke/README.md` for the plan to
turn this into a repeatable driver.

## Screens captured

| File | Screen | Notes |
|---|---|---|
| `01_launch_unconfigured.png` | Home, no connection configured | Disconnected banner, "Configure a connection in Settings" |
| `02_settings_empty.png` | Settings, first open | Port pre-filled `4317` |
| `03_settings_filled.png` | Settings, host+token entered | — |
| `04_settings_saved.png` | Home, "Settings saved" snackbar | — |
| `05_home_connected.png` | Sessions tab, connected | 3 real tmux sessions, live status dots |
| `06_session_detail.png` | Session detail (`Core`) | Live pane render + quick-key buttons + send-keys box |
| `07_dashboard.png` | Dashboard tab | Real repo registry, handoff badges (orange `!`) |
| `08_repo_detail.png` | Repo detail (`amistad`) | Real now/next/blocked/momentum from its `status.md` |
| `09_quick_actions_empty.png` | Actions tab | Not actually empty — real persisted commands from a prior session |
| `10_quick_actions_add_dialog.png` | Actions, add-command dialog | — |
