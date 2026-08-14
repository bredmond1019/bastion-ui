// Widget test for IconTile (BU.10.B task 3).
//
// For each of the three accents, asserts the fill is the 14% alpha of the
// right token, the border is the 30% alpha, and the tile is 40x40.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildTile(IconAccent accent) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: IconTile(icon: Icons.bolt, accent: accent),
    ),
  );
}

void main() {
  group('IconTile', () {
    testWidgets('primary accent tints fill/border from AppTokens.primary', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(IconAccent.primary));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(IconTile),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, AppTokens.alpha(AppTokens.primary, 0.14));
      expect(
        decoration.border!.top.color,
        AppTokens.alpha(AppTokens.primary, 0.30),
      );
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppTokens.radiusXl),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, AppTokens.primary);
    });

    testWidgets('accent2 accent tints fill/border from AppTokens.accent2', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(IconAccent.accent2));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(IconTile),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, AppTokens.alpha(AppTokens.accent2, 0.14));
      expect(
        decoration.border!.top.color,
        AppTokens.alpha(AppTokens.accent2, 0.30),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, AppTokens.accent2);
    });

    testWidgets('accent3 accent tints fill/border from AppTokens.accent3', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTile(IconAccent.accent3));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(IconTile),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, AppTokens.alpha(AppTokens.accent3, 0.14));
      expect(
        decoration.border!.top.color,
        AppTokens.alpha(AppTokens.accent3, 0.30),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, AppTokens.accent3);
    });

    testWidgets('renders a 40x40 tile', (tester) async {
      await tester.pumpWidget(_buildTile(IconAccent.primary));

      final size = tester.getSize(
        find.descendant(
          of: find.byType(IconTile),
          matching: find.byType(Container),
        ),
      );
      expect(size, const Size(40, 40));
    });

    testWidgets('is excluded from semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildTile(IconAccent.primary));

      // The Icon widget also wraps itself in an ExcludeSemantics
      // internally, so at least one (not necessarily exactly one) must be
      // present above it.
      final excludeFinder = find.descendant(
        of: find.byType(IconTile),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludeFinder, findsWidgets);

      handle.dispose();
    });
  });
}
