// Widget test for PanelCard (BU.10.B task 1).
//
// Asserts the card's decoration resolves its background, border, and
// radius from AppTokens rather than a hardcoded literal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildCard() {
  return MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(body: PanelCard(child: Text('panel content'))),
  );
}

void main() {
  group('PanelCard', () {
    testWidgets('resolves background, border, and radius from AppTokens', (
      tester,
    ) async {
      await tester.pumpWidget(_buildCard());

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, AppTokens.surface);
      expect(decoration.border, Border.all(color: AppTokens.line, width: 1));
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppTokens.radiusXxl),
      );
    });

    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_buildCard());

      expect(find.text('panel content'), findsOneWidget);
    });

    testWidgets('shows a focus ring while a descendant holds focus', (
      tester,
    ) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PanelCard(child: TextField(focusNode: focusNode)),
          ),
        ),
      );

      Container containerOf() => tester.widget<Container>(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Container),
        ),
      );

      expect((containerOf().decoration! as BoxDecoration).boxShadow, isEmpty);

      focusNode.requestFocus();
      await tester.pump();

      final focusedDecoration = containerOf().decoration! as BoxDecoration;
      expect(focusedDecoration.boxShadow, isNotEmpty);
      expect(
        focusedDecoration.boxShadow!.first.color,
        AppTokens.alpha(AppTokens.accent2, 0.5),
      );

      focusNode.dispose();
    });
  });
}
