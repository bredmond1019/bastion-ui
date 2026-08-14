// Widget test for Eyebrow (BU.10.B task 4).
//
// Asserts the rendered text is uppercased regardless of input casing, that
// the text style's family is the mono family and its colour is
// AppTokens.accent2, that letterSpacing is 0.16 * fontSize, and that the
// dot is 7dp with a non-null glow shadow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/theme/typography.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildEyebrow(String label) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Eyebrow(label: label)),
  );
}

void main() {
  group('Eyebrow', () {
    testWidgets('uppercases mixed-case input', (tester) async {
      await tester.pumpWidget(_buildEyebrow('mixed Case Label'));

      expect(find.text('MIXED CASE LABEL'), findsOneWidget);
      expect(find.text('mixed Case Label'), findsNothing);
    });

    testWidgets('uppercases already-lowercase input', (tester) async {
      await tester.pumpWidget(_buildEyebrow('lowercase'));

      expect(find.text('LOWERCASE'), findsOneWidget);
    });

    testWidgets('label style is mono family, accent2 colour, 0.16em '
        'letter-spacing', (tester) async {
      await tester.pumpWidget(_buildEyebrow('status'));

      final text = tester.widget<Text>(find.text('STATUS'));
      final style = text.style!;

      expect(style.fontFamily, AppTypography.labelMedium.fontFamily);
      expect(style.color, AppTokens.accent2);
      expect(style.letterSpacing, 0.16 * AppTypography.labelMedium.fontSize!);
    });

    testWidgets('dot is 7dp with a non-null glow shadow in accent2', (
      tester,
    ) async {
      await tester.pumpWidget(_buildEyebrow('status'));

      final dotFinder = find.descendant(
        of: find.byType(Eyebrow),
        matching: find.byType(Container),
      );
      final dot = tester.widget<Container>(dotFinder);
      final decoration = dot.decoration! as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, AppTokens.accent2);
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(decoration.boxShadow!.first.color, AppTokens.accent2);
      expect(decoration.boxShadow!.first.blurRadius, 12);
      expect(decoration.boxShadow!.first.spreadRadius, 1);

      final size = tester.getSize(dotFinder);
      expect(size, const Size(7, 7));
    });
  });
}
