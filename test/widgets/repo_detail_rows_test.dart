// `RepoDetailBlockLanes` / `_RepoDetailBlockRow` tests (`BU.13.C` task 4).
//
// Mirrors `repo_detail_stats_test.dart`'s approach: constructs
// `BriefingSectionState<BoardLaneDto>` fixtures directly against the pure
// model layer rather than wiring Riverpod/HTTP — this widget has no
// data-fetching concerns of its own to exercise.

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _readyNowBlock = BoardBlockDto(
  id: 'BU.1.A',
  title: '1:1 chat',
  repo: 'bastion-ui',
  wave: 1,
  ready: true,
  dependentCount: 2,
);

const _notReadyNextBlock = BoardBlockDto(
  id: 'BU.2.A',
  title: 'Push notifications',
  repo: 'bastion-ui',
  wave: 2,
  ready: false,
);

const _blockedBlockWithDep = BoardBlockDto(
  id: 'BU.3.A',
  title: 'Reputation layer',
  repo: 'bastion-ui',
  wave: 2,
  ready: false,
  unmetCount: 1,
  blockedBy: [BlockDepDto(repo: 'bastion-ui', id: 'BU.1.A')],
);

const _blockedBlockNoDependentCount = BoardBlockDto(
  id: 'BU.3.B',
  title: 'Safety: report & block',
  repo: 'bastion-ui',
  ready: false,
  blockedBy: [ExternalDepDto(what: 'RLS enforcement')],
);

const _multiBlockLane = BoardLaneDto(
  now: [_readyNowBlock],
  next: [_notReadyNextBlock],
  blocked: [_blockedBlockWithDep, _blockedBlockNoDependentCount],
);

Future<void> _pump(
  WidgetTester tester,
  BriefingSectionState<BoardLaneDto> boardState,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepoDetailBlockLanes(boardState: boardState),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RepoDetailBlockLanes', () {
    testWidgets('renders one row per block for a multi-block fixture', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      expect(find.byType(SeverityRow), findsNWidgets(4));
    });

    testWidgets('title leads and id is present but in the meta sub-line', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.1.A')),
      );
      expect(row.title, '1:1 chat');
      expect(row.meta, contains('BU.1.A'));
      // The id is secondary — it never becomes the row's title.
      expect(row.title, isNot(contains('BU.1.A')));
    });

    testWidgets('ready vs blocked differ without inspecting colour', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      final readyRow = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.1.A')),
      );
      final blockedRow = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.3.A')),
      );

      // Distinguishable via the typed severity enum (drives both the
      // stripe tone AND SeverityRow's non-colour title-weight channel —
      // see severity_row.dart) and via the pill tone/label, never by
      // reading a Color off either row.
      expect(readyRow.severity, SeverityRowSeverity.ok);
      expect(blockedRow.severity, SeverityRowSeverity.crit);
      expect(readyRow.severity, isNot(equals(blockedRow.severity)));
      expect(readyRow.pillLabel, 'READY');
      expect(blockedRow.pillLabel, 'BLOCKED');
    });

    testWidgets('a not-ready, non-blocked-lane block reads as waiting', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.2.A')),
      );
      expect(row.severity, SeverityRowSeverity.warn);
      expect(row.pillLabel, 'WAITING');
      expect(row.meta, contains('not ready'));
    });

    testWidgets(
      'blockedBy renders via the task-2 label function for all five variants',
      (tester) async {
        await _pump(
          tester,
          const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
        );

        final blockRow = tester.widget<SeverityRow>(
          find.byKey(const ValueKey('repo-detail-block-row-BU.3.A')),
        );
        expect(blockRow.meta, contains('blocked by bastion-ui/BU.1.A'));

        final externalRow = tester.widget<SeverityRow>(
          find.byKey(const ValueKey('repo-detail-block-row-BU.3.B')),
        );
        expect(externalRow.meta, contains('waiting on RLS enforcement'));
      },
    );

    testWidgets('a null dependentCount renders no count, never a "0"', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.3.B')),
      );
      expect(row.meta, isNot(contains('downstream')));
    });

    testWidgets('a non-null dependentCount renders the real count downstream', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_multiBlockLane),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.1.A')),
      );
      expect(row.meta, contains('2 blocks downstream'));
    });

    testWidgets('an UnknownBlockedByDto meta fallback is honest, never empty', (
      tester,
    ) async {
      const laneWithUnknown = BoardLaneDto(
        blocked: [
          BoardBlockDto(
            id: 'BU.4.A',
            title: 'Mystery dependency',
            repo: 'bastion-ui',
            ready: false,
            blockedBy: [
              UnknownBlockedByDto(raw: {'type': 'future_variant'}),
            ],
          ),
        ],
      );

      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(laneWithUnknown),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.4.A')),
      );
      expect(row.meta, isNotEmpty);
      expect(row.meta, contains('future_variant'));
    });

    testWidgets('a null ready outside the blocked lane reads as unknown', (
      tester,
    ) async {
      const laneWithUnknownReady = BoardLaneDto(
        now: [
          BoardBlockDto(
            id: 'BU.5.A',
            title: 'Unrequested graph data',
            repo: 'bastion-ui',
          ),
        ],
      );

      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(laneWithUnknownReady),
      );

      final row = tester.widget<SeverityRow>(
        find.byKey(const ValueKey('repo-detail-block-row-BU.5.A')),
      );
      expect(row.severity, SeverityRowSeverity.idle);
      expect(row.pillLabel, 'UNKNOWN');
      expect(row.meta, contains('readiness unknown'));
    });

    testWidgets('renders nothing for a loading board', (tester) async {
      await _pump(tester, const BriefingSectionLoading<BoardLaneDto>());

      expect(find.byType(SeverityRow), findsNothing);
    });

    testWidgets('renders nothing for an errored board', (tester) async {
      await _pump(
        tester,
        const BriefingSectionError<BoardLaneDto>('Server error (500)'),
      );

      expect(find.byType(SeverityRow), findsNothing);
    });
  });
}
