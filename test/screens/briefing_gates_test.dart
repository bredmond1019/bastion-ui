// `BriefingGatesLane` tests (`BU.13.B` task 5).
//
// `BriefingGatesLane` takes an already-resolved `BriefingViewModel` plus an
// explicit `now`, so these tests construct fixtures directly against the
// pure model layer (`briefing_model.dart`, task 1) rather than wiring
// Riverpod/HTTP — same pattern as `briefing_header_test.dart`.

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

final _now = DateTime.utc(2026, 8, 14, 12, 0, 0);

const _lowGate = BoardBlockDto(
  id: 'BA.1.A',
  title: 'Low blast radius gate',
  repo: 'bastion',
  blockedBy: [
    OperatorDepDto(
      slug: 'BU.ticket.low',
      exit: 'decision recorded',
      start: '2026-08-01',
      what: 'operator sign-off',
    ),
  ],
  dependentCount: 1,
);

const _highGate = BoardBlockDto(
  id: 'BA.2.A',
  title: 'High blast radius gate',
  repo: 'bastion-ui',
  blockedBy: [
    ApprovalDepDto(
      slug: 'BU.ticket.high',
      what: 'ship approval',
      digest: 'abc123',
    ),
  ],
  dependentCount: 7,
);

const _unknownGate = BoardBlockDto(
  id: 'BA.3.A',
  title: 'Unknown blast radius gate',
  repo: 'mev',
  blockedBy: [
    OperatorDepDto(
      slug: 'BU.ticket.unknown',
      exit: 'decision recorded',
      start: '2026-08-01',
    ),
  ],
  // dependentCount omitted — ?graph=true not requested for this fixture.
);

const _boardWithGates = BoardDto(
  lanes: BoardLaneDto(blocked: [_lowGate, _highGate, _unknownGate]),
);

const _blockedSession = SessionDto(
  name: 'zzz-session',
  state: 'running',
  lastLine: 'waiting on you',
  agentState: AgentState.blocked,
);

Future<void> _pump(
  WidgetTester tester,
  BriefingViewModel viewModel, {
  void Function(BoardBlockDto gate)? onGateAct,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: BriefingGatesLane(
          viewModel: viewModel,
          now: _now,
          onGateAct: onGateAct ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('gates render in blast-radius (descending) order', (
    tester,
  ) async {
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGates),
    );

    await _pump(tester, viewModel);

    final names = tester
        .widgetList<GateCard>(find.byType(GateCard))
        .map((g) => g.name)
        .toList();

    // 7 (high) > 1 (low) > null (unknown, sorts last).
    expect(names, [
      'High blast radius gate',
      'Low blast radius gate',
      'Unknown blast radius gate',
    ]);
  });

  testWidgets('a null blast radius renders an em dash, never a zero', (
    tester,
  ) async {
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGates),
    );

    await _pump(tester, viewModel);

    final blastRadiusTexts = tester
        .widgetList<Text>(find.byKey(const ValueKey('gate-card-blast-radius')))
        .map((t) => t.data)
        .toList();

    expect(blastRadiusTexts, ['7', '1', '—']);
    expect(blastRadiusTexts, isNot(contains('0')));
  });

  testWidgets('tapping a gate card fires onAct with that gate', (tester) async {
    BoardBlockDto? acted;
    final viewModel = BriefingViewModel(
      board: const BriefingSectionLoaded(_boardWithGates),
    );

    await _pump(tester, viewModel, onGateAct: (gate) => acted = gate);

    // First rendered card is the highest blast radius (7 -> _highGate).
    final actionButtons = find.byKey(const ValueKey('gate-card-action'));
    expect(actionButtons, findsNWidgets(3));
    await tester.tap(actionButtons.first);
    await tester.pump();

    expect(acted, _highGate);
  });

  testWidgets('needs-input age chips render a pinned age deterministically', (
    tester,
  ) async {
    final viewModel = BriefingViewModel(
      sessions: const BriefingSectionLoaded([_blockedSession]),
      needsInputIdle: {'zzz-session': const Duration(hours: 2)},
    );

    await _pump(tester, viewModel);

    expect(find.byType(AgeChip), findsOneWidget);
    // now (12:00) - 2h idle = 10:00 timestamp; AgeChip.since recomputes the
    // duration back to exactly 2h, formatted "2h" — pinned via the fixed
    // `_now` passed to `BriefingGatesLane`, never `DateTime.now()`.
    expect(find.text('2h'), findsOneWidget);
  });

  testWidgets(
    'a needs-input session with no tracked idle time renders no age chip',
    (tester) async {
      final viewModel = BriefingViewModel(
        sessions: const BriefingSectionLoaded([_blockedSession]),
      );

      await _pump(tester, viewModel);

      expect(find.byType(AgeChip), findsNothing);
      expect(find.text('NEEDS INPUT'), findsOneWidget);
    },
  );
}
