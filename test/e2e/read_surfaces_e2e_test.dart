/// Service-level e2e test for the four BU.11.A read surfaces: `getBoard`,
/// `getAttention`, `getDocsTree` and `getDocsFile` — boots a real `bastion
/// serve` subprocess (via [BastionServeHarness]) and drives the app's real,
/// non-mocked [BastionApi] against it, to catch wire-contract drift between
/// BastionUI's Dart DTOs and `bastion`'s `serve-api.md` v0.31 §13/§15/§16.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located — never fails on a machine without one built — unless
/// `BASTION_E2E_REQUIRE=1` is set, in which case a missing binary is a hard
/// failure (see [bastionE2eRequireBinary]).
///
/// Uses the opt-in fixture workspace ([BastionServeHarness.start]'s
/// `workspaceFixture: true`) rather than the caller's real
/// `~/.config/bastion/config.toml`, so the docs-route assertions exercise
/// known, controlled content ([kFixtureRepoName]'s `planning/status.md` +
/// `planning/handoff.md`) instead of pinning to whatever happens to be on
/// this machine's registered repos today.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/attention_dto.dart';
import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/docs_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import 'bastion_serve_harness.dart';
import 'fixtures/workspace_fixture.dart';

void main() {
  group('read surfaces e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test('getBoard/getAttention/getDocsTree/getDocsFile decode against a '
        'real bastion serve', () async {
      harness = await BastionServeHarness.start(workspaceFixture: true);
      final h = harness;
      if (h == null) {
        const whereChecked =
            'checked BASTION_BIN, ../bastion/target/release/bastion, '
            '../bastion/target/debug/bastion';
        if (bastionE2eRequireBinary()) {
          fail(
            '$bastionE2eRequireEnvVar is set but no bastion binary could '
            'be located ($whereChecked) — build one with '
            '`cargo build -p bastion` in ../bastion, or set BASTION_BIN.',
          );
        }
        markTestSkipped(
          'no bastion binary found ($whereChecked) — skipping '
          'service-level e2e test (set $bastionE2eRequireEnvVar=1 to make '
          'this a hard failure instead)',
        );
        return;
      }

      final api = BastionApi(host: h.host, port: h.port, token: h.token);
      try {
        // --- getBoard: default call leaves the three graph-gated ------
        // fields null; the ?graph=1 call proves the opt-in gate works
        // end to end by making them non-null. Only the shape is
        // asserted — no specific repo/block-id/count.
        final board = await api.getBoard();
        expect(board, isA<BoardDto>());
        expect(board.lanes, isA<BoardLaneDto>());
        final defaultBlocks = [
          ...board.lanes.now,
          ...board.lanes.next,
          ...board.lanes.blocked,
          ...board.lanes.deferred,
          ...board.lanes.finished,
        ];
        for (final block in defaultBlocks) {
          expect(block.dependentCount, isNull);
          expect(block.ready, isNull);
          expect(block.unmetCount, isNull);
        }

        final graphBoard = await api.getBoard(graph: true);
        expect(graphBoard, isA<BoardDto>());
        final graphBlocks = [
          ...graphBoard.lanes.now,
          ...graphBoard.lanes.next,
          ...graphBoard.lanes.blocked,
          ...graphBoard.lanes.deferred,
          ...graphBoard.lanes.finished,
        ];
        if (graphBlocks.isNotEmpty) {
          expect(
            graphBlocks.any(
              (b) =>
                  b.dependentCount != null ||
                  b.ready != null ||
                  b.unmetCount != null,
            ),
            isTrue,
            reason:
                'graph=1 should populate at least one graph-gated field '
                'on at least one block when any blocks exist',
          );
        }

        // --- getAttention: content-shape only --------------------------
        final attention = await api.getAttention();
        expect(attention, isA<AttentionDto>());
        expect(attention.lanes, isA<AttentionLanesDto>());
        expect(attention.lanes.staleCarryover, isA<List>());
        expect(attention.lanes.agingBacklog, isA<List>());
        expect(attention.lanes.orphanedCaptures, isA<List>());

        // --- getDocsTree: fixture repo has at least one markdown ------
        // entry (planning/status.md, planning/handoff.md). The default
        // (rootless) listing only shows the top-level "planning" directory
        // entry — scope to `path: 'planning'` to reach the files
        // themselves (`build_doc_tree_at_repo_root_lists_top_level_allowlist`
        // in `bastion/src/serve/docs.rs`).
        final tree = await api.getDocsTree(kFixtureRepoName, path: 'planning');
        expect(tree, isA<DocTreeDto>());
        expect(tree.repo, kFixtureRepoName);
        expect(tree.entries, isNotEmpty);
        expect(tree.entries, everyElement(isA<DocEntryDto>()));

        // --- getDocsFile: read a path taken from the tree above -------
        final fileEntry = tree.entries.firstWhere((e) => !e.isDir);
        final file = await api.getDocsFile(
          kFixtureRepoName,
          path: fileEntry.path,
        );
        expect(file, isA<DocFileDto>());
        expect(file.repo, kFixtureRepoName);
        expect(file.path, fileEntry.path);

        // --- Error path: a traversal path must not decode a file -----
        await expectLater(
          api.getDocsFile(kFixtureRepoName, path: '../../etc/passwd'),
          throwsA(isA<ApiError>()),
        );
      } finally {
        api.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
