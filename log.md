---
type: Log
title: BastionUI Development Log
description: Chronological log of work completed for BastionUI.
---

# Log — BastionUI

*Append-only working log. One dated entry per session. Newest entries at the top.*

---

## 2026-06-27

Completed spec `0.A-app-foundation` (Phase 0, Block A) across 7 tasks — all passed, review verdict PASS. Task 1 scaffolded the Flutter Android app (`com.bastionui/bastion_ui`) with riverpod, web_socket_channel, flutter_secure_storage, flutter_markdown, and flutter_local_notifications, replacing the generated `main.dart` with a `ProviderScope` root. Task 2 built the pure-Dart contract-mirroring model layer: a sealed `BastionFrame` hierarchy (`echo`, `error`, `unknown`, `malformed`) and v0 DTOs (`HealthDto`, `ErrorPayload`), with 22 round-trip unit tests. Task 3 added the secure connection provider (host/port/token all in `flutter_secure_storage`) and a settings screen with field validation. Task 4 implemented `BastionSocket` — a `WsTransport`-abstracted WebSocket service with a typed frame stream, sync status stream, capped exponential-backoff reconnect, and fatal auth detection, proven by 14 unit tests against a fake transport. Task 5 delivered `BastionApi` — a REST client with bearer auth, `GET /health → HealthDto`, typed `FatalAuthError` on 401, and 11 unit tests. Task 6 wired up the `ConnectionBanner` widget (live status strip), integrated `HomeShell` into `main.dart` for socket lifecycle management and settings routing, bringing total test count to 69 green. Task 7 was validation-only: `dart format`, `flutter analyze`, and `flutter test` all clean. Next: Phase 1 Block A (session control screens + approve buttons) — blocked until `bastion` ships serve-api v0.1 (Block D) and v0.2 (Block E).

```
1395673 chore: flow state — docs
0d13789 docs: update docs for 0.A-app-foundation
632c2d3 chore: flow state — task 7 passed
cfe749b chore: flow state — task 6 passed
d84c5ce feat: implement 0.A-app-foundation-task6
6ff58af chore: flow state — task 5 passed
d876577 feat: implement 0.A-app-foundation-task5
66c6162 chore: flow state — task 4 passed
```

---

## 2026-06-26

Phase 0 Block A (0.A-app-foundation) complete: all 7 tasks passed, review clean (no findings), branch 0.A-app-foundation-flow-2 ready to merge into main. Flutter app foundation shipped with 69 green tests covering scaffolding, pure-Dart contract mirroring, secure storage, reconnecting WebSocket socket service with capped exponential backoff, REST client, and connection-status banner.

```diff
 .gitignore                                         |  45 ++
 .metadata                                          |  30 +
 analysis_options.yaml                              |  28 +
 android/.gitignore                                 |  14 +
 android/app/build.gradle.kts                       |  45 ++
 android/app/src/debug/AndroidManifest.xml          |   7 +
 android/app/src/main/AndroidManifest.xml           |  45 ++
 .../com/bastionui/bastion_ui/MainActivity.kt       |   5 +
 .../main/res/drawable-v21/launch_background.xml    |  12 +
 .../src/main/res/drawable/launch_background.xml    |  12 +
 .../app/src/main/res/mipmap-hdpi/ic_launcher.png   | Bin 0 -> 544 bytes
 .../app/src/main/res/mipmap-mdpi/ic_launcher.png   | Bin 0 -> 442 bytes
 .../app/src/main/res/mipmap-xhdpi/ic_launcher.png  | Bin 0 -> 721 bytes
 .../app/src/main/res/mipmap-xxhdpi/ic_launcher.png | Bin 0 -> 1031 bytes
 .../src/main/res/mipmap-xxxhdpi/ic_launcher.png    | Bin 0 -> 1443 bytes
 android/app/src/main/res/values-night/styles.xml   |  18 +
 android/app/src/main/res/values/styles.xml         |  18 +
 android/app/src/profile/AndroidManifest.xml        |   7 +
 android/build.gradle.kts                           |  24 +
 android/gradle.properties                          |   6 +
 android/gradle/wrapper/gradle-wrapper.properties   |   5 +
 android/settings.gradle.kts                        |  26 +
 lib/main.dart                                      | 153 ++++++
 lib/models/dto.dart                                |  69 +++
 lib/models/frame.dart                              | 145 +++++
 lib/screens/settings_screen.dart                   | 192 +++++++
 lib/services/bastion_api.dart                      | 191 +++++++
 lib/services/bastion_socket.dart                   | 333 +++++++++++
 lib/state/connection_provider.dart                 | 174 ++++++
 lib/widgets/connection_banner.dart                 |  96 ++++
 log.md                                             |  17 +
 .../0.A-app-foundation/sdlc/sdlc-flow-state.json   | 391 +++++++++++++
 planning/0.A-app-foundation/sdlc/worklog.md        |  42 ++
 planning/0.A-app-foundation/tasks.md               |   4 +-
 planning/status.md                                 |   8 +-
 pubspec.lock                                       | 610 +++++++++++++++++++++
 pubspec.yaml                                       |  96 ++++
 test/models/frame_test.dart                        | 234 ++++++++
 test/services/api_test.dart                        | 193 +++++++
 test/services/reconnect_test.dart                  | 414 ++++++++++++++
 test/state/connection_provider_test.dart           | 244 +++++++++
 test/widget_test.dart                              | 101 ++++
 test/widgets/connection_banner_test.dart           | 124 +++++
 43 files changed, 4172 insertions(+), 6 deletions(-)
```

---

## 2026-06-26

Project initialized from `base-template` (commit `5afd222c8f43af0094800f3bebc64fbdfb4bd167`) via `/new-project`.
Planning infrastructure scaffolded: `planning/context.md`, `planning/status.md`,
`planning/master-plan.md`, `planning/index.md`, `planning/harness.json`, `planning/decisions/`,
and the root `CLAUDE.md` / `README.md`. Concept folders (`planning/<concept>/`) are created on
demand by the SDLC pipeline. Curated SDLC harness (`.claude/`) in place.

Next step: run `/generate-tasks` for the first Phase 0 block to begin the pipeline.

```diff
(no code changes — planning files only)
```
