/// Service-level e2e test for the rebuilt Dashboard/Portfolio screen
/// (`BU.13.D` task 6): boots a real `bastion serve` subprocess (via
/// [BastionServeHarness]) and pumps the real, non-mocked [DashboardScreen]
/// against it, through the same seam every other `testWidgets`-based e2e
/// file in this directory uses (`bastion_serve_harness.dart` +
/// `e2e_support.dart`'s [awaitStatus] for the socket handshake), mirroring
/// `briefing_e2e_test.dart` (`BU.13.B` task 8) and
/// `repo_detail_e2e_test.dart` (`BU.13.C` task 6).
///
/// ## Deliberately NOT the opt-in fixture workspace
///
/// Like `repo_detail_e2e_test.dart` and unlike this directory's
/// `workspaceFixture: true` files, this test does **not** pass
/// `workspaceFixture: true`. `GET /api/board` (this screen's only data
/// source, via `briefingBoardProvider`) never reads the `[workspaces]`
/// `config.toml` `XDG_CONFIG_HOME` registry that seam controls — the board
/// handler walks up from the server process's working directory to the
/// brain root (`mev::brain::config::find_brain_root`) and reads that
/// brain's real `brain.toml` tier registry instead. A synthetic
/// `fixture-repo` name is never a member of any real tier, so a fixture
/// workspace can never produce a real block record for the board endpoint
/// — see `repo_detail_e2e_test.dart`'s doc comment and
/// `bastion/src/serve/handlers/board.rs`'s module doc for the pipeline this
/// asserts against. `bastion serve` is spawned with no explicit
/// `workingDirectory` (inherits the test runner's cwd, this repo's root),
/// so `find_brain_root` walks up to the real `agentic-portfolio/brain.toml`
/// and the real, already-registered fleet of repos (including this very
/// repo, `bastion-ui`, which has shipped many closed blocks with real
/// `last_touched` timestamps by construction) answers the default
/// `scope=hq` request this screen makes.
///
/// ## What this proves that no unit/widget test can
///
/// `test/state/portfolio_ranking_test.dart` and `test/widgets/dashboard_test
/// .dart` pin `rankPortfolio`/`DashboardScreen` against hand-built JSON
/// fixtures — they prove the *logic* is correct for a given wire shape, but
/// they cannot prove that shape is what the real server actually sends.
/// This test is the end-to-end proof that task 1's `BoardBlockDto
/// .lastTouched` addition matches the real wire: it fetches the real board
/// directly (independently of the screen, mirroring `briefing_e2e_test
/// .dart`'s cross-check pattern) and asserts at least one real block in the
/// real fleet carries a non-null `last_touched`, then asserts the rebuilt
/// screen renders against that same real data without throwing and that
/// `rankPortfolio` partitions every real repo into exactly one of its three
/// tiers.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e -j1`
/// (single-tenant — e2e is single-tenant, one emulator and one port 4317,
/// per the spec's Notes). Self-skips (via `markTestSkipped`) when no
/// `bastion` binary can be located — never fails on a machine without one
/// built — unless `BASTION_E2E_REQUIRE=1` is set (see
/// [bastionE2eRequireBinary]). Before running for real: rebuild `bastion`
/// from current main first (lane trap 5 — a stale prebuilt binary silently
/// misbehaves).
@Tags(['e2e'])
library;

import 'dart:io' show HttpOverrides;

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/briefing_provider.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show ConnectionStatus;
import 'package:bastion_ui/state/portfolio_ranking.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('Portfolio (Dashboard) e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    testWidgets(
      'DashboardScreen renders real repos tiered against a real bastion '
      'serve; a real block carries last_touched from the real server',
      (tester) async {
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
              // mirrors `briefing_e2e_test.dart`/`repo_detail_e2e_test.dart`'s
              // established pattern.
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
                    home: const DashboardScreen(),
                  ),
                ),
              );

              // Let the board fetch resolve, polling under real time (this
              // pumps inside `runAsync`'s real, non-fake zone).
              const pollTimeout = Duration(seconds: 20);
              final deadline = DateTime.now().add(pollTimeout);
              var boardState = container.read(briefingBoardProvider);
              while (DateTime.now().isBefore(deadline) &&
                  boardState.isLoading) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump();
                boardState = container.read(briefingBoardProvider);
              }
              await tester.pump();

              expect(
                boardState.isLoading,
                isFalse,
                reason: 'board did not resolve within $pollTimeout',
              );
              expect(tester.takeException(), isNull);
              expect(
                boardState.isError,
                isFalse,
                reason:
                    'GET /api/board must succeed against a real bastion '
                    'serve spawned from this repo\'s own brain — a real '
                    'brain.toml is on disk',
              );

              // --- The screen renders against real data -----------------
              expect(find.byType(DashboardScreen), findsOneWidget);
              expect(find.text('Dashboard'), findsWidgets); // AppBar title

              // --- A real block carries last_touched from the wire -------
              // Fetched independently (a second, direct `getBoard` call),
              // never re-read off the screen's own provider — this is the
              // real cross-check that task 1's DTO addition matches the
              // wire, mirroring `briefing_e2e_test.dart`'s pattern.
              final directBoard = await api.getBoard();
              final directRepos = directBoard.repos;
              expect(
                directRepos,
                isNotEmpty,
                reason:
                    'this brain\'s real board must return at least one '
                    'repo (this very repo, bastion-ui, is registered)',
              );

              final directBlocks = <BoardBlockDto>[
                for (final repo in directRepos) ...[
                  ...repo.lanes.now,
                  ...repo.lanes.next,
                  ...repo.lanes.blocked,
                  ...repo.lanes.deferred,
                  ...repo.lanes.finished,
                ],
              ];
              expect(
                directBlocks.any((b) => b.lastTouched != null),
                isTrue,
                reason:
                    'at least one real block across the real fleet must '
                    'carry a non-null last_touched — this is the '
                    'end-to-end proof that BoardBlockDto.lastTouched '
                    'matches the real wire, which no unit test can give',
              );

              // --- Real repos tier correctly ------------------------------
              // `rankPortfolio` is pure and unit-tested against hand-built
              // fixtures (`test/state/portfolio_ranking_test.dart`); here it
              // is exercised against the real fleet and must partition
              // every real repo into exactly one of its three tiers with no
              // exception thrown, and it must never fabricate an age for a
              // repo whose blocks all lack last_touched (task 1/2's
              // never-worked vs. stale distinction, re-asserted here against
              // real data rather than a fixture).
              final now = DateTime.now();
              final ranking = rankPortfolio(directRepos, now: now);
              expect(
                ranking.all.length,
                directRepos.length,
                reason:
                    'every real repo must land in exactly one tier — a '
                    'mismatch means rankPortfolio dropped or duplicated a '
                    'real repo',
              );
              // A never-worked repo CAN legitimately land in needs-attention
              // (it has a blocked block, or an open gate) — the rule this
              // guards is narrower: it must never land there via the
              // drift-promotion (fabricated-staleness) path, which only
              // fires for a *known* recency (see `rankPortfolio`'s module
              // doc). So for every never-worked entry that IS
              // needs-attention, at least one of the two non-staleness
              // reasons must actually hold.
              for (final entry in ranking.all) {
                if (entry.recency is RepoRecencyNeverWorked &&
                    entry.tier == PortfolioTier.needsAttention) {
                  expect(
                    entry.blockedCount > 0 || entry.hasOpenGate,
                    isTrue,
                    reason:
                        '${entry.name} has never recorded a last_touched '
                        'on any block, so it must only land in '
                        'needs-attention via a blocked block or an open '
                        'gate — never via fabricated staleness',
                  );
                }
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
            'no bastion binary found ($whereChecked) — skipping Portfolio '
            'e2e (set $bastionE2eRequireEnvVar=1 to make this a hard '
            'failure instead)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
