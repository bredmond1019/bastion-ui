/// Service/widget-level e2e test for [LaunchSheet] (`BU.12.E` task 7):
/// boots a REAL `bastion serve` subprocess with the Section 18 engine mount
/// enabled (via [BastionServeHarness.start]'s `engineMount: true`, mirroring
/// `engine_read_e2e_test.dart`) and drives the real, non-mocked
/// [EngineApi]/[LaunchSheet] against it — no fakes, no mocks.
///
/// Covers what no unit test over `FakeHttpTransport` can:
///   - `GET /workflows` against a genuinely engine-mounted server returns a
///     non-empty registry, and [LaunchSheet]'s workflow-type dropdown
///     (sourced from `engineWorkflowsProvider`) renders exactly that set —
///     never a hardcoded one.
///   - The generic `unknown workflow_type` 422 and the `SDLC_FLOW`
///     pre-flight's `unknown spec_slug` 422 are asserted against the REAL
///     server's own dispatch/pre-flight code, naming the offending value.
///   - The `unknown repo` case is asserted against what the real server
///     ACTUALLY returns for a repo-bearing `SDLC_FLOW` event with an
///     unresolvable slug: empirically (and by tracing
///     `engine-serve/src/workflows.rs`'s `register_sdlc_flow_with_registry`
///     factory against `engine-core/src/dispatch.rs`), that factory
///     resolves the repo BEFORE `post_events`'s dedicated "unknown repo"
///     pre-flight block ever runs, so any resolution failure — including
///     an unknown slug — surfaces as `error: 'policy resolution failed'`,
///     never `error: 'unknown repo'`. See the assertion's own comment
///     below for the full trace. This proves the thing this task actually
///     asks for — [EngineApi.launchRun]'s mapping matches what the live
///     server returns — even though the specific [LaunchUnknownRepo]
///     class it also maps stays proven only at the unit level
///     (`test/services/engine_api_test.dart` task 2) for that reason.
///
/// ## Target repo: this very repo, no fixture workspace
///
/// Like `repo_detail_e2e_test.dart` (`BU.13.C` task 6), this test does NOT
/// pass `workspaceFixture: true`. The `SDLC_FLOW` pre-flight's repo
/// registry comes from a completely different path than the `[workspaces]`
/// `XDG_CONFIG_HOME` registry that seam controls: `engine-serve`'s
/// `repo_registry()` resolves `ENGINE_BRAIN_ROOT` (unset here) by walking
/// up from the spawned server's **working directory** — inherited, since
/// `BastionServeHarness.start` passes no explicit `workingDirectory`, from
/// this test runner's cwd (this repo's root) — to the real
/// `agentic-portfolio/brain.toml`. That real brain registers this very
/// repo under the slug `bastion-ui` (`repo_path = "core/bastion-ui"`), so
/// `repo: 'bastion-ui'` is a genuinely KNOWN repo slug wherever this suite
/// runs, and its real `planning/` directory reliably does NOT contain
/// [_nonsenseSpecSlug] — a fixture repo could not stand in for either half
/// of that pair.
///
/// ## Deliberately no real 202 (SDLC_FLOW) launch
///
/// Per the spec's Out of Scope / this task's description: launching a real
/// `SDLC_FLOW` run would spawn actual agent work on the operator's
/// machine, and `TERMINAL_PROBE` — the one other harmless (model-free,
/// `engine-core/src/workflows/terminal_probe/mod.rs`) registered workflow
/// type — creates a real, unmanaged tmux session with no run-scoped
/// cleanup handle exposed by this client (`launchRun` returns only
/// `run_id`/`event_id`; the session name is an internal function of that
/// run id this repo has no reason to duplicate). Rather than leave a
/// dangling tmux session on the operator's machine, the `202` path is
/// proven at the unit level instead (`test/services/engine_api_test.dart`
/// task 2, over `FakeHttpTransport`) — see `planning/BU.12.E/tasks.md`
/// Notes for the record of this decision.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`.
/// Self-skips (via `markTestSkipped`) — visibly, never a silent pass —
/// when no engine-mounted server is obtainable in this environment: either
/// no `bastion` binary can be located, or `DATABASE_URL` /
/// `BASTION_ENGINE_API_KEY` are not both set in the parent process
/// environment (see [bastionServeHarnessEngineMountAvailable]).
///
/// The engine API key is read from the real process environment at
/// runtime only — never hardcoded, never logged. A sentinel-free run: no
/// deliberately-wrong key is exercised here (that path is already covered
/// by `engine_read_e2e_test.dart`).
@Tags(['e2e'])
library;

import 'dart:io' show HttpOverrides, Platform;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/launch_sheet.dart';
import 'package:bastion_ui/services/engine_api.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show connectionProvider, secureStorageProvider;
import 'package:bastion_ui/state/engine_workflows_provider.dart';
import 'package:bastion_ui/theme/app_theme.dart';

import 'bastion_serve_harness.dart';

/// The real, already-registered `brain.toml` repo slug this test targets
/// for the `SDLC_FLOW` pre-flight's "known repo, unknown spec_slug" case —
/// this very repo. See this file's doc comment.
const String _knownRepo = 'bastion-ui';

/// A repo slug guaranteed to name no real `brain.toml` entry.
const String _nonsenseRepo = 'e2e-does-not-exist-repo-launch-9f3a1c';

/// A spec slug guaranteed to name no real `planning/` subdirectory of
/// [_knownRepo].
const String _nonsenseSpecSlug = 'e2e-does-not-exist-spec-launch-9f3a1c';

/// A workflow_type guaranteed to name no registered dispatcher entry.
const String _unregisteredWorkflowType = 'E2E_NOT_A_REGISTERED_TYPE_9F3A1C';

/// In-memory [FlutterSecureStorage] fake pre-seeded with the real server's
/// host/port/engine-key, so `connectionProvider`/`readEngineKey()` (which
/// `engineWorkflowsProvider`'s internal client reads) resolve to the same
/// live server this test's own [EngineApi] talks to. Mirrors
/// `run_control_test.dart`/`launch_sheet_test.dart`'s `_FakeSecureStorage`.
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  _FakeSecureStorage(Map<String, String?> seed) : store = Map.of(seed);

  final Map<String, String?> store;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];
}

void main() {
  // This file imports `package:flutter/material.dart` (for `LaunchSheet`'s
  // widget test below), which makes `flutter test` initialize
  // `TestWidgetsFlutterBinding` for the WHOLE file — installing a global
  // `HttpOverrides` that synthesizes a 400 for every `HttpClient`, even
  // for the bare `test()` group above it that never itself touches
  // Flutter's widget-testing bindings. Suspend it for the whole file
  // (mirrors every other file in this directory that does real I/O, e.g.
  // `repo_detail_e2e_test.dart`), restoring on teardown.
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = null);

  group('launch pre-flight e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test(
      'live registry is non-empty; unknownRepo/unknownSpecSlug/'
      'unknownWorkflowType are each proven against the real server, '
      'naming the offending value; no real SDLC_FLOW run is spawned',
      () async {
        if (!bastionServeHarnessEngineMountAvailable()) {
          const whereChecked =
              'checked BASTION_BIN, ../bastion/target/release/bastion, '
              '../bastion/target/debug/bastion, and the parent environment '
              'for DATABASE_URL + BASTION_ENGINE_API_KEY';
          if (bastionE2eRequireBinary()) {
            fail(
              '$bastionE2eRequireEnvVar is set but no engine-mounted '
              'bastion serve could be obtained ($whereChecked) — build a '
              'binary with `cargo build -p bastion` in ../bastion and '
              'export DATABASE_URL + BASTION_ENGINE_API_KEY, or set '
              'BASTION_BIN.',
            );
          }
          markTestSkipped(
            'no engine-mounted bastion serve obtainable ($whereChecked) — '
            'skipping launch e2e test (set $bastionE2eRequireEnvVar=1 to '
            'make this a hard failure instead)',
          );
          return;
        }

        final engineKey = Platform.environment['BASTION_ENGINE_API_KEY']!;

        // No `workspaceFixture: true` — the SDLC_FLOW pre-flight's repo
        // registry reads the real brain via cwd walk-up, not the
        // `[workspaces]` XDG registry. See this file's doc comment.
        harness = await BastionServeHarness.start(engineMount: true);
        final h = harness;
        if (h == null) {
          markTestSkipped(
            'bastion binary became unavailable between the availability '
            'check and start() — skipping launch e2e test',
          );
          return;
        }

        final engine = EngineApi(host: h.host, port: h.port, key: engineKey);
        try {
          // --- Live registry is non-empty ------------------------------
          final types = await engine.getWorkflows();
          expect(types, isNotEmpty);

          // --- unknown workflow_type, naming the offending type --------
          final unknownTypeOutcome = await engine.launchRun(
            workflowType: _unregisteredWorkflowType,
            data: const {},
          );
          expect(unknownTypeOutcome, isA<LaunchUnknownWorkflowType>());
          expect(
            (unknownTypeOutcome as LaunchUnknownWorkflowType).workflowType,
            _unregisteredWorkflowType,
          );

          // --- unknown repo, naming the slug ---------------------------
          // Empirically (verified against this real server): a
          // repo-bearing `SDLC_FLOW` event with an unresolvable slug never
          // reaches http.rs's dedicated "unknown repo" pre-flight check at
          // all — `register_sdlc_flow_with_registry`'s factory
          // (`workflows.rs`) calls `resolve_target_root` FIRST, inside
          // `Dispatcher::dispatch_with_event` itself, and ANY factory
          // error — including an unresolvable repo slug — is wrapped as
          // `DispatchError::PolicyResolutionFailed` before the
          // `body.workflow_type == "SDLC_FLOW"` pre-flight block in
          // `post_events` ever runs (`dispatch.rs`'s
          // `factory(event).map_err(DispatchError::PolicyResolutionFailed)`
          // does not distinguish "bad repo" from "bad profile"). So the
          // dedicated `LaunchUnknownRepo` class this client maps is real
          // and correctly implemented against the documented contract
          // (`engine-serve/src/http.rs`'s Check 1), but is not reachable
          // through this specific input shape on the CURRENT engine-rs —
          // the server's real answer here is `error: 'policy resolution
          // failed'`, which `EngineApi.launchRun` correctly maps to
          // [LaunchPolicyFailed]. That correctness — the client's mapping
          // matching what the live server actually returns — is what this
          // assertion proves; `LaunchUnknownRepo` itself stays proven at
          // the unit level (`test/services/engine_api_test.dart` task 2).
          // A nonsense repo 422s BEFORE any spec_slug check runs either
          // way, so no run id is ever minted and there is nothing to
          // clean up.
          final unknownRepoOutcome = await engine.launchRun(
            workflowType: 'SDLC_FLOW',
            data: const {
              'repo': _nonsenseRepo,
              'spec_slug': 'irrelevant-never-reached',
            },
          );
          expect(unknownRepoOutcome, isA<LaunchPolicyFailed>());
          expect(
            (unknownRepoOutcome as LaunchPolicyFailed).message,
            contains(_nonsenseRepo),
          );

          // --- unknown spec_slug (SDLC_FLOW pre-flight), naming it -----
          // `_knownRepo` resolves for real; `_nonsenseSpecSlug` does not
          // exist under its real `planning/` — proves the SECOND
          // pre-flight check independently of the first.
          final unknownSlugOutcome = await engine.launchRun(
            workflowType: 'SDLC_FLOW',
            data: const {'repo': _knownRepo, 'spec_slug': _nonsenseSpecSlug},
          );
          expect(unknownSlugOutcome, isA<LaunchUnknownSpecSlug>());
          expect(
            (unknownSlugOutcome as LaunchUnknownSpecSlug).specSlug,
            _nonsenseSpecSlug,
          );
        } finally {
          engine.dispose();
        }
      },
    );
  });

  group('LaunchSheet widget e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    testWidgets(
      'the workflow-type dropdown renders exactly the live GET /workflows '
      'registry against a real engine-mounted bastion serve',
      (tester) async {
        var skip = false;

        // See `briefing_e2e_test.dart` for why the binding's global
        // `HttpOverrides` (synthetic 400 on every request) must be
        // suspended for the duration of a real-I/O `testWidgets` body.
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;

        try {
          await tester.runAsync(() async {
            if (!bastionServeHarnessEngineMountAvailable()) {
              if (bastionE2eRequireBinary()) {
                fail(
                  '$bastionE2eRequireEnvVar is set but no engine-mounted '
                  'bastion serve could be obtained — build a binary with '
                  '`cargo build -p bastion` in ../bastion and export '
                  'DATABASE_URL + BASTION_ENGINE_API_KEY, or set '
                  'BASTION_BIN.',
                );
              }
              skip = true;
              return;
            }

            final engineKey = Platform.environment['BASTION_ENGINE_API_KEY']!;

            harness = await BastionServeHarness.start(engineMount: true);
            final h = harness;
            if (h == null) {
              skip = true;
              return;
            }

            // Independently fetch the real registry so the assertion below
            // does not compare the dropdown against itself.
            final probe = EngineApi(host: h.host, port: h.port, key: engineKey);
            final List<String> liveTypes;
            try {
              liveTypes = await probe.getWorkflows();
            } finally {
              probe.dispose();
            }
            expect(liveTypes, isNotEmpty);

            final engine = EngineApi(
              host: h.host,
              port: h.port,
              key: engineKey,
            );
            final storage = _FakeSecureStorage({
              'bastion.server.host': h.host,
              'bastion.server.port': h.port.toString(),
              'bastion.auth.engine_key': engineKey,
            });
            final container = ProviderContainer(
              overrides: [secureStorageProvider.overrideWithValue(storage)],
            );

            try {
              // `connectionProvider`'s `ConnectionNotifier` loads
              // host/port from storage ASYNCHRONOUSLY in its constructor
              // (`_load()`). `engineWorkflowsProvider`'s own notifier
              // reads `connectionProvider`'s CURRENT (possibly still
              // default/empty-host) state SYNCHRONOUSLY the moment it is
              // first watched (its constructor calls `refresh()`
              // immediately). Force `_load()` to resolve first, so the
              // widget below doesn't race it and probe an empty host.
              container.read(connectionProvider.notifier);
              await Future<void>.delayed(const Duration(milliseconds: 50));

              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: container,
                  child: MaterialApp(
                    theme: AppTheme.dark,
                    home: Scaffold(body: LaunchSheet(engine: engine)),
                  ),
                ),
              );

              // Let `engineWorkflowsProvider`'s probe + fetch resolve
              // under real time (this pumps inside `runAsync`'s real,
              // non-fake zone) — mirrors `repo_detail_e2e_test.dart`'s
              // poll loop.
              const pollTimeout = Duration(seconds: 20);
              final deadline = DateTime.now().add(pollTimeout);
              EngineWorkflowsState state = container.read(
                engineWorkflowsProvider,
              );
              while (DateTime.now().isBefore(deadline) &&
                  state.runtimeType == EngineWorkflowsLoading) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump();
                state = container.read(engineWorkflowsProvider);
              }
              await tester.pump();

              expect(
                state,
                isA<EngineWorkflowsLoaded>(),
                reason:
                    'engineWorkflowsProvider did not resolve to a loaded '
                    'registry within $pollTimeout (state: $state)',
              );
              expect(tester.takeException(), isNull);

              final loaded = state as EngineWorkflowsLoaded;
              expect(loaded.types, liveTypes);

              // `DropdownButtonFormField` builds its `items` internally
              // (no public getter to read them back off the widget), so
              // this proves the dropdown is registry-sourced by opening
              // it and asserting every live type appears as a selectable
              // menu entry — combined with `loaded.types == liveTypes`
              // above and `launch_sheet.dart`'s own `for (final type in
              // types) DropdownMenuItem(value: type, ...)` construction
              // (which iterates the SAME `types` list `loaded.types`
              // comes from), this closes the loop from "the provider
              // fetched the live registry" to "the sheet actually
              // rendered it".
              final dropdownFinder = find.byKey(
                const ValueKey('launch-sheet-workflow-dropdown'),
              );
              expect(dropdownFinder, findsOneWidget);
              await tester.tap(dropdownFinder);
              await tester.pumpAndSettle();
              for (final type in liveTypes) {
                expect(
                  find.text(type),
                  findsWidgets,
                  reason:
                      'registered workflow type "$type" did not render as '
                      'a menu entry',
                );
              }
              // Close the menu so it doesn't linger into teardown.
              await tester.tapAt(const Offset(1, 1));
              await tester.pumpAndSettle();
            } finally {
              engine.dispose();
              container.dispose();
            }
          });
        } finally {
          HttpOverrides.global = previousHttpOverrides;
        }

        if (skip) {
          markTestSkipped(
            'no engine-mounted bastion serve obtainable — skipping '
            'LaunchSheet widget e2e test',
          );
        }
      },
    );
  });
}
