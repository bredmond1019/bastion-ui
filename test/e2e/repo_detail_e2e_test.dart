/// Service-level e2e test for the restructured Repo Detail screen
/// (`BU.13.C` task 6): boots a real `bastion serve` subprocess (via
/// [BastionServeHarness]) and pumps the real, non-mocked [RepoDetailScreen]
/// against it, through the same seam every other `testWidgets`-based e2e
/// file in this directory uses (`bastion_serve_harness.dart` +
/// `e2e_support.dart`'s [awaitStatus] for the socket handshake), mirroring
/// `briefing_e2e_test.dart` (`BU.13.B` task 8).
///
/// ## Deliberately NOT the opt-in fixture workspace
///
/// Unlike this directory's other files, this test does **not** pass
/// `workspaceFixture: true`. That seam (`fixtures/workspace_fixture.dart`)
/// only controls `GET /api/repos/{name}/status|handoff|workflows` — the
/// `[workspaces]` registry `bastion serve` reads via `XDG_CONFIG_HOME`. The
/// typed block records this screen restructures around
/// (`GET /api/board?scope=project&repo=<name>&graph=true`) come from a
/// completely different path: `bastion`'s board handler walks up from the
/// server process's **working directory** to the brain root
/// (`mev::brain::config::find_brain_root`) and reads that brain's
/// `brain.toml` tier registry — untouched by `XDG_CONFIG_HOME`. A fixture
/// repo name (`fixture-repo`) is never a member of any real tier, so
/// `scope=project&repo=fixture-repo` would deterministically resolve to an
/// empty `repos: []` match, forever — there is no way to get the fixture
/// workspace to produce a real block record. See `board.rs`'s module doc
/// (`bastion/src/serve/handlers/board.rs`) for the pipeline this asserts
/// against.
///
/// So this test targets **this very repo** (`bastion-ui`) by name instead —
/// the one real, already-registered-in-`brain.toml` repo guaranteed to be
/// on disk wherever this suite runs (it IS this suite). `bastion serve` is
/// spawned with no explicit `workingDirectory` (inherits the test runner's
/// cwd, this repo's root), so `find_brain_root` walks up to the real
/// `agentic-portfolio/brain.toml`, and `bastion-ui`'s own real
/// `planning/status.md` / `planning/state.json` (tracks with closed blocks)
/// answer the request — this is the only way to assert "real block records
/// render as rows" truthfully; a synthetic fixture repo cannot produce one.
/// Asserts are tolerant of `now`/`next`/`blocked` (day-to-day state) but
/// require the `finished` lane to be non-empty — this repo has shipped many
/// closed blocks by construction, so an empty finished lane would itself be
/// a signal something is broken.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e -j1`
/// (single-tenant emulator/port 4317 — see the spec's Notes for the actual
/// recorded run). Self-skips (via `markTestSkipped`) when no `bastion`
/// binary can be located, unless `BASTION_E2E_REQUIRE=1` is set (see
/// [bastionE2eRequireBinary]).
@Tags(['e2e'])
library;

import 'dart:io' show HttpOverrides;

import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show ConnectionStatus;
import 'package:bastion_ui/state/repo_board_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/state/workflows_provider.dart'
    show repoWorkflowsProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

/// The repo this test drives the screen for — this very repo. It is real,
/// on disk, and already a `brain.toml` `core`-tier member wherever this
/// suite runs, so `GET /api/board?scope=project&repo=bastion-ui&graph=true`
/// returns real block records rather than an empty synthetic-fixture match.
const String _targetRepo = 'bastion-ui';

void main() {
  group('Repo detail e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    testWidgets('RepoDetailScreen renders real block records as rows for '
        '$_targetRepo against a real bastion serve', (tester) async {
      var skip = false;

      // See `briefing_e2e_test.dart` for why the binding's global
      // `HttpOverrides` (synthetic 400 on every request) must be
      // suspended for the duration of a real-I/O `testWidgets` body.
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;

      try {
        await tester.runAsync(() async {
          // No `workspaceFixture: true` — see this file's doc comment.
          harness = await BastionServeHarness.start();
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
            // mirrors `main.dart`'s real app-shell order and
            // `briefing_e2e_test.dart`'s established pattern.
            // `repoWorkflowsProvider` watches the shared socket's
            // `workflow_done` event stream, so it must be set before the
            // screen mounts.
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
                  home: const RepoDetailScreen(repoName: _targetRepo),
                ),
              ),
            );

            // Let the status/workflow fetch and the board fetch both
            // resolve, polling under real time (this pumps inside
            // `runAsync`'s real, non-fake zone).
            const pollTimeout = Duration(seconds: 20);
            final deadline = DateTime.now().add(pollTimeout);
            var workflowsState = container.read(
              repoWorkflowsProvider(_targetRepo),
            );
            var boardState = container.read(repoBoardProvider(_targetRepo));
            while (DateTime.now().isBefore(deadline) &&
                (workflowsState.loading || boardState.isLoading)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              await tester.pump();
              workflowsState = container.read(
                repoWorkflowsProvider(_targetRepo),
              );
              boardState = container.read(repoBoardProvider(_targetRepo));
            }
            await tester.pump();

            expect(
              workflowsState.loading,
              isFalse,
              reason:
                  'repo status/workflows did not resolve within '
                  '$pollTimeout',
            );
            expect(
              boardState.isLoading,
              isFalse,
              reason: 'repo board did not resolve within $pollTimeout',
            );
            expect(tester.takeException(), isNull);
            expect(
              boardState.isError,
              isFalse,
              reason:
                  'GET /api/board?scope=project&repo=$_targetRepo '
                  'must succeed against a real bastion serve pointed at '
                  'this repo\'s own brain — a real repo/tier is on disk',
            );

            // --- The screen renders against real data -----------------
            expect(find.byType(RepoDetailScreen), findsOneWidget);
            expect(find.text(_targetRepo), findsWidgets); // AppBar title
            expect(
              find.byKey(const ValueKey('repo-detail-stats')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('repo-detail-block-lanes')),
              findsOneWidget,
            );

            // --- Real block records render as rows ---------------------
            // Tolerant on now/next/blocked (day-to-day, can legitimately
            // be empty right now), but this repo has shipped many closed
            // blocks by construction — the finished lane must be
            // non-empty, and every finished block must have produced its
            // own SeverityRow (never a comma-joined run).
            final lanes = boardState.dataOrNull;
            expect(
              lanes,
              isNotNull,
              reason: 'board resolved without error but carries no data',
            );
            expect(
              lanes!.finished,
              isNotEmpty,
              reason:
                  '$_targetRepo has closed blocks in its real '
                  'planning/state.json — an empty finished lane means '
                  'the board pipeline did not actually reach real data',
            );

            final allBlocks = [
              ...lanes.now,
              ...lanes.next,
              ...lanes.blocked,
              ...lanes.deferred,
              ...lanes.finished,
            ];
            expect(allBlocks, isNotEmpty);

            final rowFinder = find.byType(SeverityRow);
            expect(
              rowFinder,
              findsNWidgets(allBlocks.length),
              reason:
                  'one SeverityRow must render per real block record — '
                  'a mismatch means rows collapsed into a joined run or '
                  'were dropped',
            );

            // Spot-check one real finished block's id/title actually
            // reached the widget tree (not just the count).
            final sample = lanes.finished.first;
            expect(
              find.byKey(ValueKey('repo-detail-block-row-${sample.id}')),
              findsOneWidget,
            );
            expect(find.text(sample.title), findsWidgets);

            // --- No comma-joined run of block records ------------------
            // Mirrors `repo_detail_empty_test.dart`'s guard: the exact
            // regression this block exists to fix is a single Text node
            // stringing 2+ distinct block ids together as a bare-comma
            // run (e.g. "BU.1.A, BU.2.A"). A row's own meta line
            // legitimately packs several facts about *one* block
            // separated by ` · ` — that is not the regression.
            final commaJoinedIds = RegExp(
              r'BU\.\d+\.[A-Z](?:,\s*BU\.\d+\.[A-Z])+',
            );
            final rendered = tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data ?? '');
            for (final text in rendered) {
              expect(
                commaJoinedIds.hasMatch(text),
                isFalse,
                reason:
                    'found a comma-joined run of block ids in a single '
                    'Text widget: "$text"',
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
          'no bastion binary found ($whereChecked) — skipping Repo '
          'detail e2e (set $bastionE2eRequireEnvVar=1 to make this a '
          'hard failure instead)',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
