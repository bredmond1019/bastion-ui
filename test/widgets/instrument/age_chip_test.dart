// Widget test for AgeChip (BU.13.A task 1).
//
// Covers every format boundary (59s/60s/59m/60m/23h/24h), asserts the tone
// flips to StatusTones.warning at the staleness threshold (resolved tone,
// not the string), and asserts tabular figures are applied.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildChip(Duration age, {Duration? staleThreshold}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: AgeChip(
        age: age,
        staleThreshold: staleThreshold ?? kDefaultAgeChipStaleThreshold,
      ),
    ),
  );
}

void main() {
  group('formatAgeChipLabel boundaries', () {
    final cases = <Duration, String>{
      const Duration(seconds: 59): 'just now',
      const Duration(seconds: 60): '1m',
      const Duration(minutes: 59): '59m',
      const Duration(minutes: 60): '1h',
      const Duration(hours: 23): '23h',
      const Duration(hours: 24): '1d',
    };

    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(formatAgeChipLabel(entry.key), entry.value);
      });
    }
  });

  group('AgeChip', () {
    testWidgets('renders the formatted label', (tester) async {
      await tester.pumpWidget(_buildChip(const Duration(minutes: 4)));

      expect(find.text('4m'), findsOneWidget);
    });

    testWidgets('below threshold resolves the neutral tone', (tester) async {
      await tester.pumpWidget(
        _buildChip(
          const Duration(hours: 1),
          staleThreshold: const Duration(hours: 24),
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('1h'));
      expect(text.style!.color, tones.neutral.foreground);

      final containerFinder = find.descendant(
        of: find.byType(AgeChip),
        matching: find.byType(Container),
      );
      final container = tester.widget<Container>(containerFinder.first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, tones.neutral.background);
      expect(decoration.border!.top.color, tones.neutral.border);
    });

    testWidgets('at threshold resolves the warning tone', (tester) async {
      await tester.pumpWidget(
        _buildChip(
          const Duration(hours: 24),
          staleThreshold: const Duration(hours: 24),
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('1d'));
      expect(text.style!.color, tones.warning.foreground);

      final containerFinder = find.descendant(
        of: find.byType(AgeChip),
        matching: find.byType(Container),
      );
      final container = tester.widget<Container>(containerFinder.first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, tones.warning.background);
      expect(decoration.border!.top.color, tones.warning.border);
    });

    testWidgets('past threshold resolves the warning tone', (tester) async {
      await tester.pumpWidget(
        _buildChip(
          const Duration(days: 9),
          staleThreshold: const Duration(hours: 24),
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('9d'));
      expect(text.style!.color, tones.warning.foreground);
    });

    testWidgets('applies tabular figures to the label', (tester) async {
      await tester.pumpWidget(_buildChip(const Duration(minutes: 4)));

      final text = tester.widget<Text>(find.text('4m'));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('AgeChip.since computes age from an injected now', () {
      final now = DateTime(2026, 8, 14, 12, 0, 0);
      final timestamp = now.subtract(const Duration(minutes: 4));

      final chip = AgeChip.since(timestamp, now: now);

      expect(chip.age, const Duration(minutes: 4));
    });
  });
}
