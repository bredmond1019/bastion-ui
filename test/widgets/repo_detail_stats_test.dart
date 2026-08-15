// `RepoDetailStats` tests (`BU.13.C` task 3).
//
// `RepoDetailStats` takes an already-resolved
// `BriefingSectionState<BoardLaneDto>`, so these tests construct fixtures
// directly against the pure model layer (`briefing_model.dart`) rather than
// wiring Riverpod/HTTP — the stat row has no data-fetching concerns of its
// own to exercise.

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

const _laneNowBlock = BoardBlockDto(
  id: 'BU.1.A',
  title: 'A now block',
  repo: 'bastion-ui',
);
const _laneNextBlock1 = BoardBlockDto(
  id: 'BU.2.A',
  title: 'A next block',
  repo: 'bastion-ui',
);
const _laneNextBlock2 = BoardBlockDto(
  id: 'BU.2.B',
  title: 'Another next block',
  repo: 'bastion-ui',
);
const _laneBlockedBlock = BoardBlockDto(
  id: 'BU.3.A',
  title: 'A blocked block',
  repo: 'bastion-ui',
);

const _laneWithAllThree = BoardLaneDto(
  now: [_laneNowBlock],
  next: [_laneNextBlock1, _laneNextBlock2],
  blocked: [_laneBlockedBlock],
);

const _laneEmpty = BoardLaneDto();

Future<void> _pump(
  WidgetTester tester,
  BriefingSectionState<BoardLaneDto> boardState,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: RepoDetailStats(boardState: boardState)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RepoDetailStats', () {
    testWidgets('counts equal the fixture lane lengths', (tester) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_laneWithAllThree),
      );

      expect(find.text('1'), findsNWidgets(2)); // now=1, blocked=1
      expect(find.text('2'), findsOneWidget); // next=2

      final tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
      expect(tiles, hasLength(3));
      expect(tiles[0].label, 'now');
      expect(tiles[0].value, '1');
      expect(tiles[1].label, 'next');
      expect(tiles[1].value, '2');
      expect(tiles[2].label, 'blocked');
      expect(tiles[2].value, '1');
    });

    testWidgets('zero-blocked renders calm, not critical', (tester) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_laneEmpty),
      );

      final blockedTile = tester
          .widgetList<StatTile>(find.byType(StatTile))
          .firstWhere((t) => t.label == 'blocked');
      expect(blockedTile.value, '0');
      expect(blockedTile.severity, StatTileSeverity.neutral);
    });

    testWidgets('a non-zero blocked count carries the danger tone', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_laneWithAllThree),
      );

      final blockedTile = tester
          .widgetList<StatTile>(find.byType(StatTile))
          .firstWhere((t) => t.label == 'blocked');
      expect(blockedTile.severity, StatTileSeverity.danger);
    });

    testWidgets('an errored board renders an em dash, never a zero', (
      tester,
    ) async {
      await _pump(
        tester,
        const BriefingSectionError<BoardLaneDto>('Server error (500)'),
      );

      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('0'), findsNothing);

      final blockedTile = tester
          .widgetList<StatTile>(find.byType(StatTile))
          .firstWhere((t) => t.label == 'blocked');
      expect(blockedTile.severity, StatTileSeverity.neutral);
    });

    testWidgets(
      'an unloaded (loading) board renders an em dash, never a zero',
      (tester) async {
        await _pump(tester, const BriefingSectionLoading<BoardLaneDto>());

        expect(find.text('—'), findsNWidgets(3));
        expect(find.text('0'), findsNothing);
      },
    );
  });
}
