---
type: Reference
title: BastionUI Test Tiers
description: The three test tiers BastionUI runs, what each one catches, and what it costs to run.
doc_id: testing
layer: [surface]
project: bastion-ui
status: active
keywords: [testing, integration-tests, e2e, patrol, coverage-guard, dev-environment, emulator]
related: [architecture, api-reference]
---

# BastionUI Test Tiers

## What this page is for

You are about to add or change code and need to know which tests must come with it, or
a check went red and you need to know what that tier was even asking. BastionUI carries
three test tiers; each answers a different question, and each costs something different
to run.

## Quickstart

Typed in a terminal at this repo's root:

```bash
dart format --output=none --set-exit-if-changed lib test   # gating
flutter analyze                                            # gating
flutter test --exclude-tags e2e                            # gating: tiers 1 + 2
flutter test --tags e2e                                    # tier 3, NOT gating; self-skips with no `bastion` binary
```

The three gating commands come from `planning/harness.json` (that directory is a symlink
into the private brain vault and is not in this public repo). The SDLC engines read the
commands from there — change them there, never in a `workflows/*.js` engine.

| Tier | Answers | Cost | Gating |
|---|---|---|---|
| [1. Unit + widget](#1-unit--widget--gated-mocked) | Does this function/widget behave in isolation? | cheap | yes |
| [2. Integration](#2-integration--gated-real-client--real-providers-over-a-routing-fake) | Does the real client still speak the wire contract? | cheap | yes |
| [3. E2E + Patrol](#3-e2e--patrol--non-gating-needs-a-real-server-and-a-device) | Does a real server still speak this, on a real device? | expensive | no |

## 1. Unit + widget — gated, mocked

**Question it answers:** does this function/widget/notifier behave correctly in isolation?

**Cost:** cheap. Pure Dart, no I/O, no device. Runs as part of `flutter test --exclude-tags
e2e`.

**Shape:** individual test files under `test/models/`, `test/services/`, `test/state/`,
`test/widgets/`, `test/theme/`, etc. Each historically hand-rolled its own mocked HTTP
transport; six of these have since been migrated onto the shared fixture described below
(`BU.ticket.integration-test-tier` task 6).

## 2. Integration — gated, real client + real providers over a routing fake

**Question it answers:** does the client still speak the `bastion serve` wire contract
correctly? Does a real `BastionApi` send the request the server expects, and do the real
riverpod providers reach correct state from a realistic response?

**Cost:** cheap — still pure Dart, no external process — but exercises real production code
(`BastionApi`, `HttpTransport`, the provider layer) rather than mocks of it, so it catches
request-shape and decode drift that unit tests mocking `BastionApi` itself cannot see.

**Shape:** lives under `test/integration/`, backed by shared fixtures under
`test/support/`:

- `test/support/fake_http_transport.dart` — a routing `HttpTransport` fake. Responses are
  registered per `(method, path)`; an unmatched request fails the test naming the offending
  method and full URL rather than silently falling through to another route's body. It
  records every request's method, path, decoded query parameters, headers and body.
- `test/support/wire_fixtures.dart` — one wire-shaped payload per route `BastionApi`
  consumes, each carrying a comment naming the `serve-api.md` section (or the local DTO,
  when the sibling `bastion` checkout is unavailable) it mirrors.
- `test/integration/bastion_api_integration_test.dart` — drives every public `BastionApi`
  method through the routing fake; asserts request path, query encoding, the `Authorization:
  Bearer` header, the decoded return value, and the error contract (`401` → `FatalAuthError`,
  other non-2xx → the client's existing error type, malformed 200 JSON → a loud failure).
- `test/integration/providers_integration_test.dart` — builds a real `ProviderContainer`
  with only `bastionApiProvider` overridden (per decision D2: the single root container with
  overrides, never a nested scope) and asserts `reposProvider`, `sessionsProvider` and
  `workflowsProvider` reach correct state, including the refresh-failure-keeps-prior-state
  case.
- `test/integration/api_coverage_guard_test.dart` — a source sweep, not reflection, modelled
  on `test/theme/no_color_literals_test.dart`. It reads `lib/services/bastion_api.dart` off
  disk, enumerates `BastionApi`'s public route methods, and fails naming any method with no
  reference under `test/integration/`.

These tests are deliberately untagged so they run inside the same gating command as tier 1:
`flutter test --exclude-tags e2e`. Tagging them `integration` would either leave them in the
gating suite anyway or require a new harness check outside the gate that runs on every task
— either way it would put the drift detector somewhere it does not belong.

**The rule for adding a route:** a new `BastionApi` method needs a fixture in
`wire_fixtures.dart`, an integration case in `bastion_api_integration_test.dart`, and (tier
3, below) an e2e case. The coverage guard enforces the middle one mechanically — it fails
the build if you forget it.

## 3. E2E + Patrol — non-gating, needs a real server and a device

**Question it answers:** does the real server still speak this, end to end, on a real
device/emulator?

**Cost:** expensive. Needs a built `bastion` binary reachable over the tailnet and a
connected device/emulator. Tagged `e2e` and excluded from the default gating command; run
explicitly with `flutter test --tags e2e`.

**Shape:** two independent non-gating checks, both self-skipping when their prerequisite
is missing, both run by hand (this project's `testDepth` is `fast`, so the SDLC engines
never auto-run a `gates: false` check):

| Check | Command (terminal, repo root) | Needs |
|---|---|---|
| `e2e-serve-contract` | `flutter test --tags e2e` | A built `bastion` binary; spawns a real `bastion serve` and drives the app's real network clients against it |
| `patrol-visual-smoke` | `scripts/run_patrol_smoke.sh` | An attached Android device/emulator **and** a built `bastion` binary; drives the real UI and captures screenshots (convention: `visual_smoke/README.md`) |

To get both prerequisites up in one call, use `scripts/start_dev_env.sh` — see
[Manual dev environment](#manual-dev-environment--device--a-real-bastion-serve) below.

## What no tier can verify

Whether a fixture in `wire_fixtures.dart` still matches what `bastion serve` actually emits
is evidence that lives in another repo's working tree (`../bastion/docs/serve-api.md`) and
in another process (a running server) — no check in this repo can observe it. That fidelity
question is the non-gating `e2e-serve-contract` check's job, not the integration tier's. The
integration tier proves the client *encodes requests and decodes responses the way the
fixtures say it should*; it cannot prove the fixtures are still correct.

### Every tier builds *debug*, so release-only defects are invisible

Unit, widget, integration, the `e2e` tag and Patrol all run debug builds. Anything that
differs between debug and release is therefore unobservable to every check in this repo.

This is not hypothetical. On 2026-08-18 a manual `flutter run --release` pass found that
`android.permission.INTERNET` was declared only in `android/app/src/debug/AndroidManifest.xml`
and `.../profile/` — Flutter's default scaffolding — and never in `main`. **Every release build
therefore had no network access at all**, failing each socket with
`SocketException: OS Error: Operation not permitted, errno = 1`. For a thin client over
`bastion serve` that is total failure: the app installs and does nothing.

The suite was fully green throughout, because the debug manifest supplied the permission to
every test. `test/android_manifest_test.dart` now pins that one symptom, but the general class
remains unguarded — periodically driving a real `--release` build is the only thing that closes
it. See `visual_smoke/README.md` for the capture convention.

## Manual dev environment — device + a real `bastion serve`

Tier 3 (and any other by-hand check against a live server, e.g. verifying a fix, running
Patrol manually, or just clicking around against real data) needs an attached Android
device/emulator plus a reachable `bastion serve`. `scripts/start_dev_env.sh` sets both up in
one call and bails with a specific diagnosis rather than a generic failure:

```bash
scripts/start_dev_env.sh            # boot emulator + server, then `flutter run` against it
scripts/start_dev_env.sh --no-run   # same, but stop after printing connection info
```

What it does, in order:

1. Sets `ANDROID_HOME`/`JAVA_HOME`/`PATH` (same defaults as `run_patrol_smoke.sh`).
2. Reuses an already-attached device (`adb devices`), or boots the `Pixel_9` AVD (override
   with `--avd <name>`) and waits for it to finish booting.
3. Locates a `bastion` binary — `../bastion/target/release/`, then `.../debug/`, then
   `$PATH` (override with `BASTION_BIN=/path/to/bastion`).
4. Reuses an already-answering `bastion serve` on `:4317` (override with `--port`), or starts
   one — sourcing `../bastion/.env` first so `DATABASE_URL`/`BASTION_ENGINE_API_KEY` are
   picked up and the engine routes mount (see `D6` in `planning/decisions/`). Reports whether
   the engine actually mounted, since `BU.12.x` calls 404 silently otherwise.
5. On success, either execs `flutter run -d <device>`, or (with `--no-run`) prints the
   host:port + token to plug into Settings.

**Failure modes it distinguishes** (each bails with the specific cause + where to look, never
just "something went wrong"): missing Android SDK, no AVD by that name, emulator boot
timeout, no `bastion` binary found, the target port already held by something that isn't
`bastion serve` (names the PID/process, doesn't just fail to bind), and `bastion serve`
exiting immediately or never answering `/health` (both dump the server's own log tail). It
only tears down what it started, and only on a failure path — a clean run leaves the
emulator and server up so repeated `flutter run`s don't pay the boot cost again.
