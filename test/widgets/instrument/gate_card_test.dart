// Widget test for GateCard (BU.13.A task 6).
//
// Covers: name, waiting-on text and blast radius all render; the primary
// action callback fires on tap; the blast-radius count uses tabular
// figures; a zero/unknown blast radius degrades gracefully to an em dash.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

Widget _buildCard({
  required String name,
  required String waitingOn,
  required int? blastRadius,
  required VoidCallback onAct,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: GateCard(
        name: name,
        waitingOn: waitingOn,
        blastRadius: blastRadius,
        onAct: onAct,
      ),
    ),
  );
}

void main() {
  group('GateCard', () {
    testWidgets('renders the name, waiting-on text, and blast radius', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildCard(
          name: 'Ship the operator instrument',
          waitingOn: 'your review',
          blastRadius: 6,
          onAct: () {},
        ),
      );

      expect(find.text('Ship the operator instrument'), findsOneWidget);
      expect(find.text('your review'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('fires the callback when the primary action is tapped', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildCard(
          name: 'Gate',
          waitingOn: 'CI',
          blastRadius: 2,
          onAct: () => tapped = true,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('gate-card-action')));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('the blast radius count uses tabular figures', (tester) async {
      await tester.pumpWidget(
        _buildCard(
          name: 'Gate',
          waitingOn: 'your review',
          blastRadius: 12,
          onAct: () {},
        ),
      );

      final text = tester.widget<Text>(find.text('12'));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('a null blast radius degrades to an em dash', (tester) async {
      await tester.pumpWidget(
        _buildCard(
          name: 'Gate',
          waitingOn: 'your review',
          blastRadius: null,
          onAct: () {},
        ),
      );

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a zero blast radius degrades to an em dash', (tester) async {
      await tester.pumpWidget(
        _buildCard(
          name: 'Gate',
          waitingOn: 'your review',
          blastRadius: 0,
          onAct: () {},
        ),
      );

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a negative blast radius degrades to an em dash', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildCard(
          name: 'Gate',
          waitingOn: 'your review',
          blastRadius: -1,
          onAct: () {},
        ),
      );

      expect(find.text('—'), findsOneWidget);
    });
  });
}
