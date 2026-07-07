---
type: Index
title: BastionUI
description: Flutter mobile Surface (Android phone + tablet) for remotely operating the whole Bastion practice OS over Tailscale, backed by a bastion serve HTTP+WebSocket API.
doc_id: readme
layer: [surface]
project: bastion-ui
status: active
keywords: [Flutter, mobile surface, BastionUI, bastion serve, WebSocket, Android]
related: [context, status, master-plan, planning-index]
---

# BastionUI

> Part of the **Bastion** ecosystem — see the [bastion-os](https://github.com/bredmond1019/bastion-os) front door for the full architecture.

Flutter mobile Surface (Android phone + tablet) for remotely operating the whole Bastion practice OS over Tailscale, backed by a bastion serve HTTP+WebSocket API.

## Prerequisites

- Flutter SDK (Dart `^3.12.2`, per `pubspec.yaml`)
- A running `bastion serve` instance reachable over Tailscale (see the `bastion` repo's
  [serve-api docs](https://github.com/bredmond1019/bastion/blob/main/docs/serve-api.md)) — this app is a thin client with no backend of its own
- An Android device/emulator (or `flutter run -d <device>` target) for live end-to-end use

## Setup

```bash
flutter pub get   # install dependencies
```

On first launch, open the Settings screen (gear icon) and enter the `bastion serve` host,
port, and bearer token. The token is stored via `flutter_secure_storage`.

## Running locally

```bash
flutter run                # run on a connected device/emulator
flutter build apk          # build an Android APK
```

## Tests

```bash
dart format --output=none --set-exit-if-changed . # format check (gating)
flutter analyze                                    # static analysis (gating)
flutter test                                        # unit + widget tests (gating)
```

## Directory map

```
bastion-ui/
├── .claude/        ← Claude Code commands + SDLC workflow engines
├── planning/       ← context, status, master-plan, harness.json, decisions/, <concept>/
└── <source dirs>
```

## Documentation

| Doc | Contents |
|---|---|
| [planning/context.md](planning/context.md) | Orientation + governing principles |
| [planning/master-plan.md](planning/master-plan.md) | Strategy + phase specifications |
| [planning/status.md](planning/status.md) | Current progress |
| [planning/harness.json](planning/harness.json) | SDLC validation/UI-test config (see `harness.examples.md`) |
| [planning/decisions/index.md](planning/decisions/index.md) | Settled implementation decisions (append-only) |

## Roadmap / Known limitations

- **No known blocking limitations.** High-frequency WebSocket state streams are debounced (RxDart) to prevent rebuild thrashing; one-shot input prompts remain undebounced by design. Future work: offline caching and reconnection/backoff resilience.

---

*Initialized 2026-06-26 from `base-template` (commit `5afd222c8f43af0094800f3bebc64fbdfb4bd167`).*
