// Widget test for HeadingRule (BU.10.B task 5).
//
// Asserts the size is 56x3, the radius is fully rounded, and the
// gradient's colours are AppTokens.primary and AppTokens.accent3 in that
// order.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildRule() {
  return MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(body: HeadingRule()),
  );
}

void main() {
  group('HeadingRule', () {
    testWidgets('renders a 56x3 bar', (tester) async {
      await tester.pumpWidget(_buildRule());

      final size = tester.getSize(find.byType(HeadingRule));
      expect(size.width, 56);
      expect(size.height, 3);
    });

    testWidgets('is fully rounded and gradient runs primary -> accent3', (
      tester,
    ) async {
      await tester.pumpWidget(_buildRule());

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(HeadingRule),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      final radius = decoration.borderRadius! as BorderRadius;

      expect(gradient.colors, [AppTokens.primary, AppTokens.accent3]);
      expect(gradient.begin, Alignment.centerLeft);
      expect(gradient.end, Alignment.centerRight);
      // Fully rounded: radius >= half the shorter dimension (3dp tall bar).
      expect(radius.topLeft.x, greaterThanOrEqualTo(1.5));
      expect(radius, BorderRadius.circular(AppTokens.radiusXxxxl));
    });

    testWidgets('is excluded from semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildRule());

      final excludeFinder = find.descendant(
        of: find.byType(HeadingRule),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludeFinder, findsOneWidget);

      handle.dispose();
    });
  });
}
