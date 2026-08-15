// `BriefingHeader` tests (`BU.13.B` task 4).
//
// `BriefingHeader` takes an already-resolved `BriefingViewModel`, so these
// tests construct fixtures directly against the pure model layer
// (`briefing_model.dart`, task 1) rather than wiring Riverpod/HTTP — the
// header widget has no data-fetching concerns of its own to exercise.

import 'package:bastion_ui/models/attention_dto.dart';
import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/briefing_screen.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _gateBlock = BoardBlockDto(
  id: 'BA.1.A',
  title: 'A gate',
  repo: 'bastion',
  blockedBy: [
    OperatorDepDto(
      slug: 'BU.ticket.review',
      exit: 'decision recorded',
      start: '2026-08-01',
      what: 'operator sign-off',
    ),
  ],
  dependentCount: 3,
);

const _boardWithGate = BoardDto(lanes: BoardLaneDto(blocked: [_gateBlock]));

const _blockedCarryover = AttentionCarryoverDto(
  repo: 'bastion-ui',
  slug: 'BU.ticket.blocked-thing',
  kind: 'known_issue',
  text: 'blocked on something',
  thresholdDays: 10,
  lane: 'blocking',
  ageDays: 12,
  clearsWhenSatisfied: false,
);

const _attentionWithBlocked = AttentionDto(
  asOf: '2026-08-14',
  lanes: AttentionLanesDto(staleCarryover: [_blockedCarryover]),
  thresholds: AttentionThresholdsDto(
    envDays: 14,
    deferredDays: 21,
    knownIssueDays: 10,
    constraintDays: 30,
    backlogDays: 45,
  ),
);

const _runningSession = SessionDto(name: 'alpha', state: 'running');
const _blockedSession = SessionDto(
  name: 'beta',
  state: 'running',
  agentState: AgentState.blocked,
);

Future<void> _pump(WidgetTester tester, BriefingViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: BriefingHeader(viewModel: viewModel)),
    ),
  );
}

void main() {
  testWidgets('the three counts equal the fixture lane counts', (tester) async {
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGate),
      attention: const BriefingSectionLoaded(_attentionWithBlocked),
      sessions: const BriefingSectionLoaded([_runningSession, _blockedSession]),
    );

    await _pump(tester, viewModel);

    // needsYouCount = 1 gate + 1 needs-input session = 2.
    expect(find.text('2'), findsOneWidget);
    // blockedCount = 1 blocking carryover; runningCount = 1 (alpha; beta
    // is needs-input, not a live run) — both tiles read "1".
    expect(find.text('1'), findsNWidgets(2));
    expect(viewModel.needsYouCount, 2);
    expect(viewModel.blockedCount, 1);
    expect(viewModel.runningCount, 1);
  });

  testWidgets('an errored section renders an em dash, never a zero', (
    tester,
  ) async {
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGate),
      attention: const BriefingSectionError('Server error (500)'),
      sessions: const BriefingSectionLoaded([_runningSession]),
    );

    await _pump(tester, viewModel);

    // blocked derives solely from the errored attention section — an
    // em dash, never a fabricated zero.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    // needs-you (board has 1 gate, sessions fine) and running (sessions
    // fine) both still render real, non-zero numbers.
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets(
    'a board error blanks needs-you but leaves blocked/running intact',
    (tester) async {
      final viewModel = BriefingViewModel(
        board: const BriefingSectionError('Server error (500)'),
        attention: const BriefingSectionLoaded(_attentionWithBlocked),
        sessions: const BriefingSectionLoaded([_runningSession]),
      );

      await _pump(tester, viewModel);

      expect(find.text('—'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2)); // blocked=1, running=1
    },
  );

  testWidgets('tiles render in consequence order: need you, blocked, running', (
    tester,
  ) async {
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGate),
      attention: const BriefingSectionLoaded(_attentionWithBlocked),
      sessions: const BriefingSectionLoaded([_runningSession, _blockedSession]),
    );

    await _pump(tester, viewModel);

    final tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
    expect(tiles, hasLength(3));
    expect(tiles[0].label, 'need you');
    expect(tiles[0].severity, StatTileSeverity.danger);
    expect(tiles[1].label, 'blocked');
    expect(tiles[1].severity, StatTileSeverity.warning);
    expect(tiles[2].label, 'running');
    expect(tiles[2].severity, StatTileSeverity.neutral);
  });
}
