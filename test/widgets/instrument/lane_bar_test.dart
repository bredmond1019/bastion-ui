// Widget test for LaneBar (BU.13.A task 3).
//
// Covers: segment order is fixed (done · now · blocked · next); segment
// proportions are correct for a representative split; the three degenerate
// cases (all-zero, single non-zero, non-round proportions) render without
// throwing; colours are tone-derived, never literal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildBar({
  required int done,
  required int now,
  required int blocked,
  required int next,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: LaneBar(done: done, now: now, blocked: blocked, next: next),
    ),
  );
}

/// Finds the [Expanded] segment for [segment] and its child [Container].
Expanded _segment(WidgetTester tester, LaneBarSegment segment) {
  return tester.widget<Expanded>(
    find.byKey(ValueKey('lanebar-segment-${segment.name}')),
  );
}

Color _fillColor(Expanded segment) {
  return (segment.child as Container).color!;
}

void main() {
  group('LaneBar', () {
    testWidgets('renders segments in the fixed order done, now, blocked, '
        'next', (tester) async {
      await tester.pumpWidget(_buildBar(done: 1, now: 1, blocked: 1, next: 1));

      final row = tester.widget<Row>(
        find.descendant(
          of: find.byType(SizedBox).first,
          matching: find.byType(Row),
        ),
      );
      final keys = row.children
          .whereType<Expanded>()
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();

      expect(keys, [
        'lanebar-segment-done',
        'lanebar-segment-now',
        'lanebar-segment-blocked',
        'lanebar-segment-next',
      ]);
    });

    testWidgets('computes correct proportions for a representative split', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildBar(done: 22, now: 14, blocked: 43, next: 21),
      );

      expect(_segment(tester, LaneBarSegment.done).flex, 220);
      expect(_segment(tester, LaneBarSegment.now).flex, 140);
      expect(_segment(tester, LaneBarSegment.blocked).flex, 430);
      expect(_segment(tester, LaneBarSegment.next).flex, 210);
    });

    testWidgets('segment colours are tone-derived', (tester) async {
      await tester.pumpWidget(
        _buildBar(done: 22, now: 14, blocked: 43, next: 21),
      );

      final tones = StatusTones.dark;
      expect(
        _fillColor(_segment(tester, LaneBarSegment.done)),
        tones.success.foreground,
      );
      expect(
        _fillColor(_segment(tester, LaneBarSegment.now)),
        tones.active.foreground,
      );
      expect(
        _fillColor(_segment(tester, LaneBarSegment.blocked)),
        tones.danger.foreground,
      );
      expect(
        _fillColor(_segment(tester, LaneBarSegment.next)),
        tones.neutral.foreground,
      );
    });

    testWidgets('all-zero counts render an empty/neutral track without '
        'throwing', (tester) async {
      await tester.pumpWidget(_buildBar(done: 0, now: 0, blocked: 0, next: 0));

      expect(tester.takeException(), isNull);
      expect(find.byType(LaneBar), findsOneWidget);
    });

    testWidgets('a single non-zero lane renders without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBar(done: 0, now: 5, blocked: 0, next: 0));

      expect(tester.takeException(), isNull);
      expect(_segment(tester, LaneBarSegment.now).flex, 1000);
    });

    testWidgets(
      'counts that do not divide evenly still fill the track exactly',
      (tester) async {
        await tester.pumpWidget(
          _buildBar(done: 1, now: 1, blocked: 1, next: 0),
        );

        expect(tester.takeException(), isNull);
        final total =
            _segment(tester, LaneBarSegment.done).flex +
            _segment(tester, LaneBarSegment.now).flex +
            _segment(tester, LaneBarSegment.blocked).flex;
        expect(total, 1000);
      },
    );

    testWidgets('renders a key row naming all four segments', (tester) async {
      await tester.pumpWidget(_buildBar(done: 1, now: 1, blocked: 1, next: 1));

      expect(find.text('done'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(find.text('blocked'), findsOneWidget);
      expect(find.text('next'), findsOneWidget);
    });
  });
}
