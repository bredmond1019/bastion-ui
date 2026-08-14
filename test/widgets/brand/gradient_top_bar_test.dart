// Widget test for GradientTopBar (BU.10.B task 2).
//
// Asserts each of the four hues resolves to its expected AppTokens colour
// pair, that the bar is 3dp tall, and that hueForIndex cycles correctly for
// 0..5 and for negative indices.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildBar(GradientHue hue) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: GradientTopBar(hue: hue)),
  );
}

void main() {
  group('GradientTopBar', () {
    testWidgets('bluePurple resolves primary -> accent3', (tester) async {
      await tester.pumpWidget(_buildBar(GradientHue.bluePurple));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GradientTopBar),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;

      expect(gradient.colors, [AppTokens.primary, AppTokens.accent3]);
      expect(gradient.begin, Alignment.centerLeft);
      expect(gradient.end, Alignment.centerRight);
      expect(container.constraints?.maxHeight ?? 3, 3);
    });

    testWidgets('blue resolves primary -> accent2', (tester) async {
      await tester.pumpWidget(_buildBar(GradientHue.blue));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GradientTopBar),
          matching: find.byType(Container),
        ),
      );
      final gradient =
          (container.decoration! as BoxDecoration).gradient! as LinearGradient;

      expect(gradient.colors, [AppTokens.primary, AppTokens.accent2]);
    });

    testWidgets('purple resolves accent3 -> primary', (tester) async {
      await tester.pumpWidget(_buildBar(GradientHue.purple));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GradientTopBar),
          matching: find.byType(Container),
        ),
      );
      final gradient =
          (container.decoration! as BoxDecoration).gradient! as LinearGradient;

      expect(gradient.colors, [AppTokens.accent3, AppTokens.primary]);
    });

    testWidgets('purpleBlue resolves accent3 -> accent2', (tester) async {
      await tester.pumpWidget(_buildBar(GradientHue.purpleBlue));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GradientTopBar),
          matching: find.byType(Container),
        ),
      );
      final gradient =
          (container.decoration! as BoxDecoration).gradient! as LinearGradient;

      expect(gradient.colors, [AppTokens.accent3, AppTokens.accent2]);
    });

    testWidgets('renders a 3dp tall bar', (tester) async {
      await tester.pumpWidget(_buildBar(GradientHue.bluePurple));

      final size = tester.getSize(find.byType(GradientTopBar));
      expect(size.height, 3);
    });

    testWidgets('is excluded from semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildBar(GradientHue.bluePurple));

      final excludeFinder = find.descendant(
        of: find.byType(GradientTopBar),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludeFinder, findsOneWidget);

      handle.dispose();
    });
  });

  group('hueForIndex', () {
    test('cycles through the four hues for 0..5', () {
      expect(hueForIndex(0), GradientHue.bluePurple);
      expect(hueForIndex(1), GradientHue.blue);
      expect(hueForIndex(2), GradientHue.purple);
      expect(hueForIndex(3), GradientHue.purpleBlue);
      expect(hueForIndex(4), GradientHue.bluePurple);
      expect(hueForIndex(5), GradientHue.blue);
    });

    test('is correct for negative indices', () {
      expect(hueForIndex(-1), GradientHue.purpleBlue);
      expect(hueForIndex(-2), GradientHue.purple);
      expect(hueForIndex(-3), GradientHue.blue);
      expect(hueForIndex(-4), GradientHue.bluePurple);
      expect(hueForIndex(-5), GradientHue.purpleBlue);
    });
  });
}
