// Widget tests for StatusBadge.
//
// Verifies each RepoBadgeState renders its icon/dot with the colour
// resolved from the ambient StatusTones extension, not a hardcoded literal
// (BU.10.A task 6).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/status_badge.dart';

Widget _buildBadge(RepoBadgeState state) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: StatusBadge(state: state)),
  );
}

void main() {
  group('StatusBadge', () {
    testWidgets('inFlight renders the info tone on the autorenew icon', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(RepoBadgeState.inFlight));

      final icon = tester.widget<Icon>(find.byIcon(Icons.autorenew));
      expect(icon.color, StatusTones.dark.info.foreground);
      expect(find.byTooltip('Workflow in flight'), findsOneWidget);
    });

    testWidgets('hasHandoff renders the warning tone on the flag icon', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(RepoBadgeState.hasHandoff));

      final icon = tester.widget<Icon>(find.byIcon(Icons.assignment_late));
      expect(icon.color, StatusTones.dark.warning.foreground);
      expect(find.byTooltip('Handoff pending'), findsOneWidget);
    });

    testWidgets('idle renders the neutral tone on the dot', (tester) async {
      await tester.pumpWidget(_buildBadge(RepoBadgeState.idle));

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, StatusTones.dark.neutral.foreground);
      expect(find.byTooltip('Idle'), findsOneWidget);
    });

    testWidgets('all three states render at the same 20dp glyph footprint', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(RepoBadgeState.inFlight));
      final inFlightIcon = tester.widget<Icon>(find.byIcon(Icons.autorenew));
      expect(inFlightIcon.size, 20);

      await tester.pumpWidget(_buildBadge(RepoBadgeState.hasHandoff));
      final handoffIcon = tester.widget<Icon>(
        find.byIcon(Icons.assignment_late),
      );
      expect(handoffIcon.size, 20);

      await tester.pumpWidget(_buildBadge(RepoBadgeState.idle));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 10);
    });

    testWidgets('falls back to StatusTones.dark when no theme extension is '
        'registered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusBadge(state: RepoBadgeState.inFlight)),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.autorenew));
      expect(icon.color, StatusTones.dark.info.foreground);
    });
  });
}
