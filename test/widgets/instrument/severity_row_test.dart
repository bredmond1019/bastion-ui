// Widget test for SeverityRow (BU.13.A task 5).
//
// Covers: the stripe renders at the right width and tone; the non-colour
// severity channel (title font weight) changes with severity, verified
// without inspecting colour; the trailing detail slot renders what it is
// given and the row survives a null slot; the meta line renders with
// tabular figures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/brand/status_pill.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildRow({
  required SeverityRowSeverity severity,
  String title = 'bastion-ui',
  StatusPillTone pillTone = StatusPillTone.blocked,
  String pillLabel = '2 GATES',
  String meta = '14 blocks · 6 blocked · touched 4m ago',
  Widget? trailingDetail,
  double stripeWidth = 3,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SeverityRow(
        severity: severity,
        title: title,
        pillTone: pillTone,
        pillLabel: pillLabel,
        meta: meta,
        trailingDetail: trailingDetail,
        stripeWidth: stripeWidth,
      ),
    ),
  );
}

Color _stripeColor(WidgetTester tester) {
  final positioned = tester.widget<Positioned>(
    find.byKey(const ValueKey('severity-row-stripe')),
  );
  return (positioned.child as ColoredBox).color;
}

void main() {
  group('SeverityRow', () {
    testWidgets('renders the stripe at the given width', (tester) async {
      await tester.pumpWidget(
        _buildRow(severity: SeverityRowSeverity.crit, stripeWidth: 5),
      );

      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('severity-row-stripe')),
      );
      expect(positioned.width, 5);
    });

    testWidgets('stripe tone is danger for crit severity', (tester) async {
      await tester.pumpWidget(_buildRow(severity: SeverityRowSeverity.crit));

      expect(_stripeColor(tester), StatusTones.dark.danger.foreground);
    });

    testWidgets('stripe tone is warning for warn severity', (tester) async {
      await tester.pumpWidget(_buildRow(severity: SeverityRowSeverity.warn));

      expect(_stripeColor(tester), StatusTones.dark.warning.foreground);
    });

    testWidgets('stripe tone is success for ok severity', (tester) async {
      await tester.pumpWidget(_buildRow(severity: SeverityRowSeverity.ok));

      expect(_stripeColor(tester), StatusTones.dark.success.foreground);
    });

    testWidgets('stripe tone is neutral for idle severity', (tester) async {
      await tester.pumpWidget(_buildRow(severity: SeverityRowSeverity.idle));

      expect(_stripeColor(tester), StatusTones.dark.neutral.foreground);
    });

    testWidgets('title weight climbs with severity — the non-colour channel, '
        'asserted without inspecting colour', (tester) async {
      final weightBySeverity = <SeverityRowSeverity, FontWeight?>{};

      for (final severity in SeverityRowSeverity.values) {
        await tester.pumpWidget(_buildRow(severity: severity));
        final text = tester.widget<Text>(
          find.byKey(const ValueKey('severity-row-title')),
        );
        weightBySeverity[severity] = text.style?.fontWeight;
      }

      // Every severity gets a distinct weight, and it climbs with
      // severity — the signal a grayscale screenshot still carries.
      expect(
        weightBySeverity.values.toSet().length,
        SeverityRowSeverity.values.length,
      );
      expect(
        weightBySeverity[SeverityRowSeverity.crit]!.value,
        greaterThan(weightBySeverity[SeverityRowSeverity.warn]!.value),
      );
      expect(
        weightBySeverity[SeverityRowSeverity.warn]!.value,
        greaterThan(weightBySeverity[SeverityRowSeverity.ok]!.value),
      );
      expect(
        weightBySeverity[SeverityRowSeverity.ok]!.value,
        greaterThan(weightBySeverity[SeverityRowSeverity.idle]!.value),
      );
    });

    testWidgets('renders the title and the trailing StatusPill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRow(
          severity: SeverityRowSeverity.crit,
          title: 'bastion-ui',
          pillLabel: '2 GATES',
        ),
      );

      expect(find.text('bastion-ui'), findsOneWidget);
      expect(find.text('2 GATES'), findsOneWidget);
      expect(find.byType(StatusPill), findsOneWidget);
    });

    testWidgets('renders the meta sub-line', (tester) async {
      const meta = '14 blocks · 6 blocked · touched 4m ago';
      await tester.pumpWidget(
        _buildRow(severity: SeverityRowSeverity.crit, meta: meta),
      );

      expect(find.text(meta), findsOneWidget);
    });

    testWidgets('meta line uses tabular figures', (tester) async {
      await tester.pumpWidget(_buildRow(severity: SeverityRowSeverity.crit));

      final text = tester.widget<Text>(
        find.byKey(const ValueKey('severity-row-meta')),
      );
      expect(
        text.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('renders the given trailing detail widget', (tester) async {
      await tester.pumpWidget(
        _buildRow(
          severity: SeverityRowSeverity.ok,
          trailingDetail: const Text('trailing-detail-probe'),
        ),
      );

      expect(find.text('trailing-detail-probe'), findsOneWidget);
    });

    testWidgets('survives a null trailing detail slot without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRow(severity: SeverityRowSeverity.idle, trailingDetail: null),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SeverityRow), findsOneWidget);
    });
  });
}
