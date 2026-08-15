// Widget test for StatTile (BU.13.A task 2).
//
// Covers: value and label render; the number uses tabular figures;
// severity selects the tone-derived colour on the number (not the label);
// colours are token-derived (StatusTones), never literal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildTile({
  required String value,
  required String label,
  StatTileSeverity severity = StatTileSeverity.neutral,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: StatTile(value: value, label: label, severity: severity),
    ),
  );
}

void main() {
  group('StatTile', () {
    testWidgets('renders the value and the uppercased label', (tester) async {
      await tester.pumpWidget(_buildTile(value: '3', label: 'need you'));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('NEED YOU'), findsOneWidget);
    });

    testWidgets('applies tabular figures to the value', (tester) async {
      await tester.pumpWidget(_buildTile(value: '12', label: 'blocked'));

      final text = tester.widget<Text>(find.text('12'));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('neutral severity resolves the neutral tone', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          value: '7',
          label: 'running',
          severity: StatTileSeverity.neutral,
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('7'));
      expect(text.style!.color, tones.neutral.foreground);
    });

    testWidgets('warning severity resolves the warning tone', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          value: '2',
          label: 'blocked',
          severity: StatTileSeverity.warning,
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('2'));
      expect(text.style!.color, tones.warning.foreground);
    });

    testWidgets('danger severity resolves the danger tone', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          value: '3',
          label: 'need you',
          severity: StatTileSeverity.danger,
        ),
      );

      final tones = StatusTones.dark;
      final text = tester.widget<Text>(find.text('3'));
      expect(text.style!.color, tones.danger.foreground);
    });

    testWidgets('the label stays in the neutral tone regardless of severity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(
          value: '3',
          label: 'need you',
          severity: StatTileSeverity.danger,
        ),
      );

      final tones = StatusTones.dark;
      final label = tester.widget<Text>(find.text('NEED YOU'));
      expect(label.style!.color, tones.neutral.foreground);
    });

    test('StatTile.toneFor maps every severity to its StatusTone', () {
      final tones = StatusTones.dark;
      expect(StatTile.toneFor(StatTileSeverity.neutral, tones), tones.neutral);
      expect(StatTile.toneFor(StatTileSeverity.warning, tones), tones.warning);
      expect(StatTile.toneFor(StatTileSeverity.danger, tones), tones.danger);
    });
  });
}
