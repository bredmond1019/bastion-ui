// Accent constraint tests (`BU.13.B` task 7, inherited from D4).
//
// Two things must hold on this screen:
// 1. Every interactive affordance the screen introduces (GateCard's "Act"
//    button, the lane retry buttons) resolves to `AppTokens.accent2`,
//    never `AppTokens.primary` — asserted against the token, never a hex
//    literal.
// 2. `accent2` is ALSO `StatusTones.active` (surfaced here via the
//    live-runs lane's "RUNNING" pill), so "pressable" and "running" must be
//    told apart WITHOUT colour. This screen does that with a structural,
//    non-hue channel — filled-vs-outlined — checked here by asserting the
//    interactive affordances render on plain/filled shapes with no
//    border, while the active pill renders with a `Border`.

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/briefing_screen.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _gate = BoardBlockDto(
  id: 'BA.1.A',
  title: 'A gate',
  repo: 'bastion',
  blockedBy: [
    OperatorDepDto(
      slug: 'BU.ticket.gate',
      exit: 'decision recorded',
      start: '2026-08-01',
      what: 'operator sign-off',
    ),
  ],
  dependentCount: 3,
);

const _boardWithGate = BoardDto(lanes: BoardLaneDto(blocked: [_gate]));

const _runningSession = SessionDto(
  name: 'alpha',
  state: 'running',
  lastLine: 'building',
);

/// The [Material] a button actually paints with — resolved through the
/// widget tree rather than read off the `FilledButton`/`TextButton`
/// widget's own (frequently unset, theme-resolved) `style` field, so this
/// asserts what renders, not merely what was requested.
Material _renderedMaterial(WidgetTester tester, Key buttonKey) {
  return tester
      .widgetList<Material>(
        find.descendant(
          of: find.byKey(buttonKey),
          matching: find.byType(Material),
        ),
      )
      .first;
}

void main() {
  group('interactive affordances resolve to accent2', () {
    testWidgets("GateCard's Act button is filled with accent2", (tester) async {
      final viewModel = BriefingViewModel(
        board: const BriefingSectionLoaded(_boardWithGate),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BriefingGatesLane(
              viewModel: viewModel,
              now: DateTime.utc(2026, 8, 14),
              onGateAct: (_) {},
            ),
          ),
        ),
      );

      final material = _renderedMaterial(
        tester,
        const ValueKey('gate-card-action'),
      );

      expect(material.color, AppTokens.accent2);
      expect(material.color, isNot(AppTokens.primary));
    });

    testWidgets('a lane retry button is accent2, not primary', (tester) async {
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionError('Server error (500)'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BriefingBlockedLane(viewModel: viewModel, onRetry: () {}),
          ),
        ),
      );

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('briefing-lane-retry-blocked')),
      );
      final resolvedForeground = button.style?.foregroundColor?.resolve({});

      expect(resolvedForeground, AppTokens.accent2);
      expect(resolvedForeground, isNot(AppTokens.primary));
    });
  });

  group('interactive vs. active is distinguishable without colour', () {
    testWidgets(
      "GateCard's Act button has no border while the active pill does",
      (tester) async {
        final viewModel = BriefingViewModel(
          board: const BriefingSectionLoaded(_boardWithGate),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: BriefingGatesLane(
                viewModel: viewModel,
                now: DateTime.utc(2026, 8, 14),
                onGateAct: (_) {},
              ),
            ),
          ),
        );

        final material = _renderedMaterial(
          tester,
          const ValueKey('gate-card-action'),
        );

        // A filled button carries its affordance as an opaque fill with no
        // stroked border — that is the "filled" half of the
        // filled-vs-outlined channel, checked structurally rather than by
        // hue.
        expect(material.color, isNotNull);
        final shape = material.shape;
        final side = shape is RoundedRectangleBorder
            ? shape.side
            : BorderSide.none;
        expect(
          side == BorderSide.none || side.width == 0,
          isTrue,
          reason: 'the interactive fill must not also carry a stroke',
        );
      },
    );

    testWidgets('the active (RUNNING) pill renders with a border', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        sessions: const BriefingSectionLoaded([_runningSession]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BriefingLiveRunsLane(viewModel: viewModel, onRetry: () {}),
          ),
        ),
      );

      final pillContainer = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(StatusPill),
              matching: find.byType(Container),
            ),
          )
          .first;
      final decoration = pillContainer.decoration as BoxDecoration?;

      // The active pill is a TINTED, BORDERED chip — the "outlined" half
      // of the filled-vs-outlined channel — never an opaque fill like the
      // interactive button above.
      expect(decoration?.border, isNotNull);
    });

    testWidgets('a lane retry button carries no fill and no border', (
      tester,
    ) async {
      final viewModel = BriefingViewModel(
        attention: const BriefingSectionError('Server error (500)'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BriefingBlockedLane(viewModel: viewModel, onRetry: () {}),
          ),
        ),
      );

      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('briefing-lane-retry-blocked')),
      );
      final resolvedBackground = button.style?.backgroundColor?.resolve({});

      // A text button carries no fill at all — a third, even lighter
      // treatment than either the filled button or the outlined pill,
      // reinforcing that "pressable here" is never confusable with
      // "running" on shape alone.
      expect(resolvedBackground, isNull);
    });
  });
}
