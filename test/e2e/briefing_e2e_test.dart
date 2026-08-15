/// Service-level e2e test for the Briefing screen (`BU.13.B` task 8): boots
/// a real `bastion serve` subprocess (via [BastionServeHarness], with the
/// opt-in fixture workspace) and pumps the real, non-mocked
/// [BriefingScreen] against it through the same seam every other file in
/// this directory uses (`bastion_serve_harness.dart` +
/// `fixtures/workspace_fixture.dart`), plus `e2e_support.dart`'s
/// [awaitStatus] for the socket handshake.
///
/// Unlike this directory's other files, this one drives a widget
/// ([testWidgets]/[WidgetTester]) rather than a bare service call — the
/// Briefing is a screen, and "renders against real data" means the actual
/// `BriefingScreen` widget tree, wired through the real root-scope
/// providers (D2: [bastionSocketProvider]/[bastionApiProvider] set on one
/// root `ProviderScope`, exactly as `main.dart`'s app shell does and
/// `test/screens/briefing_reachable_test.dart` mirrors for its fake-backed
/// widget test).
///
/// The entire body runs inside [WidgetTester.runAsync]: a `testWidgets`
/// body otherwise executes inside a `FakeAsync` zone (real `Timer`s never
/// fire unless the test framework explicitly advances fake time), which
/// would stall indefinitely on this test's real subprocess/socket/HTTP
/// I/O — the harness's `/health` poll loop, the WebSocket handshake, and
/// the provider fetches are all `Timer`-driven under the hood. `runAsync`
/// forks a real (non-fake) zone for exactly this case.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary. Self-skips (via
/// `markTestSkipped`) when no `bastion` binary can be located — never fails
/// on a machine without one built — unless `BASTION_E2E_REQUIRE=1` is set
/// (see [bastionE2eRequireBinary]).
///
/// Covers (spec task 8):
///   - the screen renders against real data (no exception, header +
///     lanes present);
///   - the header counts agree with what the real board/attention/sessions
///     endpoints return — computed independently via direct `BastionApi`
///     calls and [rankOperatorGates]/[rankBlockedBlocks]/[rankLiveRuns],
///     never re-read off the same view model the screen renders, so this
///     is a real cross-check rather than a tautology;
///   - `getBoard(graph: true)` populates blast radius end to end — mirrors
///     `read_surfaces_e2e_test.dart`'s tolerant assertion (the fixture
///     workspace has no guaranteed blocked/operator-gated block, so this
///     asserts the mechanism works when gates exist, not a specific
///     count).
@Tags(['e2e'])
library;

import 'dart:io' show HttpOverrides;

import 'package:bastion_ui/models/session_dto.dart' show AgentState;
import 'package:bastion_ui/screens/briefing_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/state/briefing_provider.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('Briefing e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess (or fixture temp dir) is left
      // behind even if an assertion above threw.
      await harness?.stop();
      harness = null;
    });

    testWidgets(
      'BriefingScreen renders against a real bastion serve; header counts '
      'agree with the real board/attention/sessions responses; '
      'getBoard(graph: true) populates blast radius end to end',
      (tester) async {
        var skip = false;

        // `TestWidgetsFlutterBinding` installs a global `HttpOverrides`
        // that makes every `HttpClient` request return a synthetic 400
        // with no real network call (`_binding_io.dart`'s
        // `setupHttpOverrides`) — this is the first `testWidgets`-based
        // e2e test in this directory, so it is the first to hit that
        // override. `BastionServeHarness`'s `/health` poll and
        // `BastionApi`'s REST calls both need a REAL `HttpClient`; suspend
        // the override for the duration and restore it afterward so no
        // other test in the same process is affected.
        final previousHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;

        try {
          await tester.runAsync(() async {
            harness = await BastionServeHarness.start(workspaceFixture: true);
            final h = harness;
            if (h == null) {
              const whereChecked =
                  'checked BASTION_BIN, ../bastion/target/release/bastion, '
                  '../bastion/target/debug/bastion';
              if (bastionE2eRequireBinary()) {
                fail(
                  '$bastionE2eRequireEnvVar is set but no bastion binary '
                  'could be located ($whereChecked) — build one with '
                  '`cargo build -p bastion` in ../bastion, or set '
                  'BASTION_BIN.',
                );
              }
              skip = true;
              return;
            }

            final api = BastionApi(host: h.host, port: h.port, token: h.token);
            final socket = BastionSocket(
              host: h.host,
              port: h.port,
              token: h.token,
            );
            final container = ProviderContainer();

            try {
              // Connect the socket FIRST, then wire the root providers —
              // mirroring `main.dart`'s real app-shell order (and
              // `sessions_live_frame_e2e_test.dart`'s established pattern).
              final connected = awaitStatus(
                socket,
                ConnectionStatus.connected,
                timeout: const Duration(seconds: 10),
              );
              socket.connect();
              await connected;
              expect(socket.status, ConnectionStatus.connected);

              container.read(bastionSocketProvider.notifier).state = socket;
              container.read(bastionApiProvider.notifier).state = api;

              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: container,
                  child: MaterialApp(
                    theme: AppTheme.dark,
                    home: const BriefingScreen(),
                  ),
                ),
              );

              // Let the two independent async section fetches (board,
              // attention — sessions is REST-seeded synchronously by its
              // own notifier) resolve, by polling the view model's own
              // loaded state under real time.
              const pollTimeout = Duration(seconds: 20);
              final deadline = DateTime.now().add(pollTimeout);
              var viewModel = container.read(briefingViewModelProvider);
              while (DateTime.now().isBefore(deadline) &&
                  (viewModel.board.isLoading ||
                      viewModel.attention.isLoading)) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump();
                viewModel = container.read(briefingViewModelProvider);
              }
              await tester.pump();

              expect(
                viewModel.board.isLoading,
                isFalse,
                reason: 'board section did not resolve within $pollTimeout',
              );
              expect(
                viewModel.attention.isLoading,
                isFalse,
                reason: 'attention section did not resolve within $pollTimeout',
              );
              expect(tester.takeException(), isNull);

              // --- The screen renders against real data ------------------
              expect(find.byType(BriefingScreen), findsOneWidget);
              expect(find.text('Briefing'), findsWidgets); // AppBar title
              expect(viewModel.board.isError, isFalse);
              expect(viewModel.attention.isError, isFalse);

              // --- Header counts agree with the real endpoints ------------
              // Computed independently (a second, direct fetch + the same
              // pure ranking functions the model uses), never by re-reading
              // the screen's own view model — otherwise this would just
              // assert the view model agrees with itself.
              final directBoard = await api.getBoard(graph: true);
              final directAttention = await api.getAttention();
              final directSessions = await api.getSessions();

              final expectedGates = rankOperatorGates(
                directBoard.lanes.blocked,
              );
              final expectedBlocked = rankBlockedBlocks(
                directAttention.lanes.staleCarryover,
              );
              final expectedRunning = rankLiveRuns(directSessions);
              final expectedNeedsInputCount = directSessions
                  .where((s) => s.agentState == AgentState.blocked)
                  .length;

              expect(
                viewModel.needsYouCount,
                expectedGates.length + expectedNeedsInputCount,
                reason:
                    'needs-you header count must match live gates + '
                    'needs-input sessions',
              );
              expect(
                viewModel.blockedCount,
                expectedBlocked.length,
                reason:
                    'blocked header count must match live stale_carryover '
                    '"blocking"-lane entries',
              );
              expect(
                viewModel.runningCount,
                expectedRunning.length,
                reason:
                    'running header count must match live running '
                    'sessions',
              );

              // --- getBoard(graph: true) blast radius end to end ----------
              // Tolerant, mirroring `read_surfaces_e2e_test.dart`: the
              // fixture workspace has no guaranteed operator-gated block, so
              // this asserts the mechanism (a gate's `dependentCount` is
              // non-null once fetched with `graph: true`) rather than a
              // specific count.
              for (final gate in expectedGates) {
                expect(
                  gate.dependentCount,
                  isNotNull,
                  reason:
                      'an operator gate returned by getBoard(graph: true) '
                      'must have a non-null dependent_count',
                );
              }
            } finally {
              container.dispose();
              await socket.dispose();
              api.dispose();
            }
          });
        } finally {
          HttpOverrides.global = previousHttpOverrides;
        }

        if (skip) {
          const whereChecked =
              'checked BASTION_BIN, ../bastion/target/release/bastion, '
              '../bastion/target/debug/bastion';
          markTestSkipped(
            'no bastion binary found ($whereChecked) — skipping Briefing '
            'e2e (set $bastionE2eRequireEnvVar=1 to make this a hard '
            'failure instead)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
