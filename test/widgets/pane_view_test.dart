// Widget tests for PaneView.
//
// Verifies the terminal ground/text colours come from AppTokens (not
// Colors.black/Colors.white literals) and the text uses AppTypography.mono
// (BU.10.A task 6).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/theme/typography.dart';
import 'package:bastion_ui/widgets/pane_view.dart';

void main() {
  group('PaneView', () {
    testWidgets('renders the given lines joined by newlines', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PaneView(lines: ['first', 'second'])),
        ),
      );

      expect(find.text('first\nsecond'), findsOneWidget);
    });

    testWidgets('ground colour is AppTokens.paper, not Colors.black', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PaneView(lines: ['hi'])),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.color, AppTokens.paper);
    });

    testWidgets(
      'text colour is AppTokens.ink and family is the mono brand family, '
      'not Colors.white',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PaneView(lines: ['hi'])),
          ),
        );

        final text = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(text.style?.color, AppTokens.ink);
        expect(text.style?.fontFamily, AppTypography.mono.fontFamily);
      },
    );
  });
}
