// Widget test for StatusPill (BU.10.B task 6).
//
// For each of the four tones asserts the background, foreground and border
// resolve from the matching StatusTones member via the theme; asserts the
// label renders uppercased in the mono family; and asserts the pill's type
// size is NOT the web dense value, so a later density regression is caught.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/theme/typography.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildPill(StatusPillTone tone, String label) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: StatusPill(tone: tone, label: label),
    ),
  );
}

void main() {
  group('StatusPill', () {
    final cases = <StatusPillTone, String>{
      StatusPillTone.onTrack: 'active',
      StatusPillTone.needsYou: 'success',
      StatusPillTone.blocked: 'danger',
      StatusPillTone.inProgress: 'neutral',
    };

    for (final entry in cases.entries) {
      testWidgets(
        '${entry.key} resolves colours from StatusTones.${entry.value} '
        'via the theme',
        (tester) async {
          await tester.pumpWidget(_buildPill(entry.key, 'status'));

          final tones = StatusTones.dark;
          final expected = switch (entry.key) {
            StatusPillTone.onTrack => tones.active,
            StatusPillTone.needsYou => tones.success,
            StatusPillTone.blocked => tones.danger,
            StatusPillTone.inProgress => tones.neutral,
          };

          final containerFinder = find.descendant(
            of: find.byType(StatusPill),
            matching: find.byType(Container),
          );
          final outer = tester.widget<Container>(containerFinder.first);
          final decoration = outer.decoration! as BoxDecoration;

          expect(decoration.color, expected.background);
          expect(decoration.border!.top.color, expected.border);

          final dotFinder = containerFinder.at(1);
          final dot = tester.widget<Container>(dotFinder);
          final dotDecoration = dot.decoration! as BoxDecoration;
          expect(dotDecoration.color, expected.foreground);

          final text = tester.widget<Text>(find.text('STATUS'));
          expect(text.style!.color, expected.foreground);
        },
      );
    }

    testWidgets('uppercases mixed-case input', (tester) async {
      await tester.pumpWidget(_buildPill(StatusPillTone.onTrack, 'Mixed Case'));

      expect(find.text('MIXED CASE'), findsOneWidget);
      expect(find.text('Mixed Case'), findsNothing);
    });

    testWidgets('label style is mono family', (tester) async {
      await tester.pumpWidget(_buildPill(StatusPillTone.onTrack, 'status'));

      final text = tester.widget<Text>(find.text('STATUS'));
      expect(text.style!.fontFamily, AppTypography.mono.fontFamily);
    });

    testWidgets('label type size is NOT the web dense value (10.5-13.5px)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPill(StatusPillTone.onTrack, 'status'));

      final text = tester.widget<Text>(find.text('STATUS'));
      final fontSize = text.style!.fontSize!;

      expect(fontSize < 10.5 || fontSize > 13.5, isTrue);
    });
  });
}
