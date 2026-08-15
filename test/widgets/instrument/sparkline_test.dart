// Widget test for Sparkline (BU.13.A task 4).
//
// Covers: seven bars render for a seven-point series; the three degenerate
// cases (fewer than seven points, all-equal values, all-zero values) render
// without throwing; bar heights are proportional to the series max.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildSparkline(List<double> values) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SizedBox(width: 200, child: Sparkline(values: values)),
    ),
  );
}

double _heightFactor(WidgetTester tester, int index) {
  final box = tester.widget<FractionallySizedBox>(
    find.descendant(
      of: find.byKey(ValueKey('sparkline-bar-$index')),
      matching: find.byType(FractionallySizedBox),
    ),
  );
  return box.heightFactor!;
}

void main() {
  group('Sparkline', () {
    testWidgets('renders seven bars for a seven-point series', (tester) async {
      await tester.pumpWidget(
        _buildSparkline(
          [1, 2, 3, 4, 5, 6, 7].map((e) => e.toDouble()).toList(),
        ),
      );

      for (var i = 0; i < 7; i++) {
        expect(find.byKey(ValueKey('sparkline-bar-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('sparkline-bar-7')), findsNothing);
    });

    testWidgets('bar heights are proportional to the series max', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSparkline([10, 5, 20]));

      expect(_heightFactor(tester, 0), closeTo(0.5, 0.001));
      expect(_heightFactor(tester, 1), closeTo(0.25, 0.001));
      expect(_heightFactor(tester, 2), closeTo(1.0, 0.001));
    });

    testWidgets('fewer than seven points renders without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSparkline([3, 6, 9]));

      expect(tester.takeException(), isNull);
      expect(find.byType(Sparkline), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('sparkline-bar-$i')), findsOneWidget);
      }
    });

    testWidgets('all values equal renders a flat, uniform row', (tester) async {
      await tester.pumpWidget(_buildSparkline([4, 4, 4, 4, 4, 4, 4]));

      expect(tester.takeException(), isNull);
      for (var i = 0; i < 7; i++) {
        expect(_heightFactor(tester, i), closeTo(1.0, 0.001));
      }
    });

    testWidgets('all zeroes renders a flat row without dividing by zero', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSparkline([0, 0, 0, 0, 0, 0, 0]));

      expect(tester.takeException(), isNull);
      for (var i = 0; i < 7; i++) {
        final factor = _heightFactor(tester, i);
        expect(factor.isNaN, isFalse);
        expect(factor, greaterThan(0));
      }
    });

    testWidgets('an empty series renders without throwing', (tester) async {
      await tester.pumpWidget(_buildSparkline(const []));

      expect(tester.takeException(), isNull);
      expect(find.byType(Sparkline), findsOneWidget);
    });
  });
}
