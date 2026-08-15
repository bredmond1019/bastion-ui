// `BriefingBlockedLane` + `BriefingLiveRunsLane` tests (`BU.13.B` task 6),
// plus the error/empty states task 6 adds to `BriefingGatesLane` (lane 1).
//
// Each lane takes an already-resolved `BriefingViewModel`, so these tests
// construct fixtures directly against the pure model layer
// (`briefing_model.dart`, task 1) rather than wiring Riverpod/HTTP — same
// pattern as `briefing_header_test.dart` / `briefing_gates_test.dart`.

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

const _oldBlocked = AttentionCarryoverDto(
  repo: 'bastion',
  slug: 'BA.1.A',
  kind: 'known_issue',
  text: 'the old one',
  thresholdDays: 10,
  lane: 'blocking',
  ageDays: 30,
  unmetBlocks: ['BA.0.A'],
  clearsWhenSatisfied: false,
);

const _youngBlocked = AttentionCarryoverDto(
  repo: 'bastion-ui',
  slug: 'BU.2.B',
  kind: 'known_issue',
  text: 'the young one',
  thresholdDays: 10,
  lane: 'blocking',
  ageDays: 5,
  unmetBlocks: ['BU.2.A'],
  clearsWhenSatisfied: false,
);

const _unknownAgeBlocked = AttentionCarryoverDto(
  repo: 'mev',
  slug: 'MV.1.A',
  kind: 'known_issue',
  text: 'snoozed, no anchor',
  thresholdDays: 10,
  lane: 'blocking',
  unmetBlocks: ['MV.0.A'],
  clearsWhenSatisfied: false,
);

const _attentionWithBlocked = AttentionDto(
  asOf: '2026-08-14',
  lanes: AttentionLanesDto(
    staleCarryover: [_youngBlocked, _oldBlocked, _unknownAgeBlocked],
  ),
  thresholds: AttentionThresholdsDto(
    envDays: 14,
    deferredDays: 21,
    knownIssueDays: 10,
    constraintDays: 30,
    backlogDays: 45,
  ),
);

const _emptyAttention = AttentionDto(
  asOf: '2026-08-14',
  lanes: AttentionLanesDto(staleCarryover: []),
  thresholds: AttentionThresholdsDto(
    envDays: 14,
    deferredDays: 21,
    knownIssueDays: 10,
    constraintDays: 30,
    backlogDays: 45,
  ),
);

const _sessionAlpha = SessionDto(
  name: 'alpha',
  state: 'running',
  lastLine: 'building',
);
const _sessionZeta = SessionDto(
  name: 'zeta',
  state: 'running',
  lastLine: 'testing',
);
const _blockedSession = SessionDto(
  name: 'blocked-one',
  state: 'running',
  agentState: AgentState.blocked,
);

Future<void> _pumpBlocked(
  WidgetTester tester,
  BriefingViewModel viewModel, {
  VoidCallback? onRetry,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: BriefingBlockedLane(
          viewModel: viewModel,
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _pumpLiveRuns(
  WidgetTester tester,
  BriefingViewModel viewModel, {
  VoidCallback? onRetry,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: BriefingLiveRunsLane(
          viewModel: viewModel,
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  );
}

Future<void> _pumpGates(
  WidgetTester tester,
  BriefingViewModel viewModel, {
  VoidCallback? onRetry,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: BriefingGatesLane(
          viewModel: viewModel,
          now: DateTime.utc(2026, 8, 14),
          onGateAct: (_) {},
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('BriefingBlockedLane', () {
    testWidgets('rows render ranked by age_days descending, null last', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionLoaded(_attentionWithBlocked),
      );

      await _pumpBlocked(tester, viewModel);

      final titles = tester
          .widgetList<SeverityRow>(find.byType(SeverityRow))
          .map((r) => r.title)
          .toList();

      expect(titles, ['bastion/BA.1.A', 'bastion-ui/BU.2.B', 'mev/MV.1.A']);
    });

    testWidgets('each row names what it is waiting on', (tester) async {
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionLoaded(_attentionWithBlocked),
      );

      await _pumpBlocked(tester, viewModel);

      expect(find.textContaining('BA.0.A'), findsOneWidget);
      expect(find.textContaining('BU.2.A'), findsOneWidget);
    });

    testWidgets('error state renders its own message and a retry', (
      tester,
    ) async {
      var retried = false;
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionError('Server error (500)'),
      );

      await _pumpBlocked(tester, viewModel, onRetry: () => retried = true);

      expect(find.text('Server error (500)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('briefing-lane-retry-blocked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-lane-empty-blocked')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('briefing-lane-retry-blocked')),
      );
      expect(retried, isTrue);
    });

    testWidgets('empty state is calm and distinct from the error state', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionLoaded(_emptyAttention),
      );

      await _pumpBlocked(tester, viewModel);

      expect(
        find.byKey(const ValueKey('briefing-lane-empty-blocked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-lane-error-blocked')),
        findsNothing,
      );
      expect(find.byType(SeverityRow), findsNothing);
    });
  });

  group('BriefingLiveRunsLane', () {
    testWidgets('rows render for running, non-needs-input sessions', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        sessions: const BriefingSectionLoaded([
          _sessionZeta,
          _sessionAlpha,
          _blockedSession,
        ]),
      );

      await _pumpLiveRuns(tester, viewModel);

      final titles = tester
          .widgetList<SeverityRow>(find.byType(SeverityRow))
          .map((r) => r.title)
          .toList();

      // Name-ascending; blocked session excluded (belongs to lane 1).
      expect(titles, ['alpha', 'zeta']);
    });

    testWidgets('error state renders its own message and a retry', (
      tester,
    ) async {
      var retried = false;
      final viewModel = BriefingViewModel(
        sessions: const BriefingSectionError('Server error (500)'),
      );

      await _pumpLiveRuns(tester, viewModel, onRetry: () => retried = true);

      expect(find.text('Server error (500)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('briefing-lane-retry-live-runs')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('briefing-lane-retry-live-runs')),
      );
      expect(retried, isTrue);
    });

    testWidgets('empty state is calm and distinct from the error state', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        sessions: const BriefingSectionLoaded([]),
      );

      await _pumpLiveRuns(tester, viewModel);

      expect(
        find.byKey(const ValueKey('briefing-lane-empty-live-runs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-lane-error-live-runs')),
        findsNothing,
      );
    });
  });

  group('BriefingGatesLane error/empty states (task 6)', () {
    testWidgets('a board error renders lane 1 error state, not empty gates', (
      tester,
    ) async {
      var retried = false;
      final viewModel = BriefingViewModel(
        board: const BriefingSectionError('Server error (500)'),
        sessions: const BriefingSectionLoaded([]),
      );

      await _pumpGates(tester, viewModel, onRetry: () => retried = true);

      expect(find.text('Server error (500)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('briefing-lane-retry-gates')),
        findsOneWidget,
      );
      expect(find.byType(GateCard), findsNothing);

      await tester.tap(find.byKey(const ValueKey('briefing-lane-retry-gates')));
      expect(retried, isTrue);
    });

    testWidgets('no gates and no needs-input renders the empty state', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        board: const BriefingSectionLoaded(
          BoardDto(lanes: BoardLaneDto(blocked: [])),
        ),
        sessions: const BriefingSectionLoaded([]),
      );

      await _pumpGates(tester, viewModel);

      expect(
        find.byKey(const ValueKey('briefing-lane-empty-gates')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('briefing-lane-error-gates')),
        findsNothing,
      );
    });
  });

  group('cross-lane isolation', () {
    testWidgets(
      'board OK + attention error: gates lane and error lane both render, '
      'blocked lane shows its own error in isolation',
      (tester) async {
        const gate = BoardBlockDto(
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
          dependentCount: 2,
        );
        final gatesViewModel = BriefingViewModel(
          board: const BriefingSectionLoaded(
            BoardDto(lanes: BoardLaneDto(blocked: [gate])),
          ),
          sessions: const BriefingSectionLoaded([]),
        );
        final blockedViewModel = BriefingViewModel(
          attention: const BriefingSectionError('Server error (500)'),
        );
        final liveRunsViewModel = BriefingViewModel(
          sessions: const BriefingSectionLoaded([_sessionAlpha]),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Column(
                children: [
                  BriefingGatesLane(
                    viewModel: gatesViewModel,
                    now: DateTime.utc(2026, 8, 14),
                    onGateAct: (_) {},
                  ),
                  BriefingBlockedLane(viewModel: blockedViewModel),
                  BriefingLiveRunsLane(viewModel: liveRunsViewModel),
                ],
              ),
            ),
          ),
        );

        // Gates lane rendered fine — unaffected by the attention failure.
        expect(find.byType(GateCard), findsOneWidget);
        // Blocked lane shows its own, isolated error.
        expect(
          find.byKey(const ValueKey('briefing-lane-error-blocked')),
          findsOneWidget,
        );
        // Live runs lane rendered fine too.
        expect(find.text('alpha'), findsOneWidget);
      },
    );
  });
}
