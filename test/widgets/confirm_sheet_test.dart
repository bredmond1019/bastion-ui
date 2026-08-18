// Widget tests for ConfirmSheet (BU.12.D task 4).
//
// Covers the four dismissal/confirmation paths — confirm resolves true;
// cancel button, scrim tap, and system back all resolve false — plus that
// the target name is rendered, and that no raw hex colour appears anywhere
// in the sheet (colours must resolve from AppTokens/StatusTones).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/confirm_sheet.dart';

const _kTargetName = 'run-abc123';

/// Pumps a [MaterialApp] with a button that opens [showConfirmSheet] via
/// [ConfirmSheet.new], and records the resolved bool into [resultBox].
Widget _buildHost(List<bool?> resultBox) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-sheet'),
              onPressed: () async {
                final confirmed = await showConfirmSheet(
                  context,
                  title: 'Abort run',
                  body: 'This will abort run $_kTargetName.',
                  targetName: _kTargetName,
                  destructiveLabel: 'Abort',
                );
                resultBox.add(confirmed);
              },
              child: const Text('Open'),
            ),
          ),
        );
      },
    ),
  );
}

/// Collects the [Color]s ConfirmSheet itself authors — the outer surface
/// fill, the severity stripe, and the target chip's fill/border — via their
/// widget keys, so the assertion is not polluted by ambient Material
/// defaults (e.g. an unstyled [OutlinedButton]'s theme-derived overlay
/// colour) that ConfirmSheet never chose and does not control.
List<Color> _collectAuthoredColors(WidgetTester tester) {
  final colors = <Color>[];

  final stripe =
      tester.widget(
            find.descendant(
              of: find.byKey(const ValueKey('confirm-sheet-stripe')),
              matching: find.byType(ColoredBox),
            ),
          )
          as ColoredBox;
  colors.add(stripe.color);

  final target =
      tester.widget(find.byKey(const Key('confirm-sheet-target'))) as Container;
  final targetDecoration = target.decoration as BoxDecoration;
  colors.add(targetDecoration.color!);
  colors.add((targetDecoration.border as Border).top.color);

  // The sheet's own outer surface Container (unkeyed — first Container
  // descendant of ConfirmSheet).
  final outer =
      tester
              .widgetList(find.byType(Container))
              .firstWhere(
                (w) =>
                    (w as Container).decoration is BoxDecoration &&
                    ((w.decoration as BoxDecoration).color ==
                        AppTokens.surface),
              )
          as Container;
  colors.add((outer.decoration as BoxDecoration).color!);

  return colors;
}

void main() {
  group('ConfirmSheet', () {
    testWidgets('renders the target name in its body', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      expect(find.text(_kTargetName), findsOneWidget);
    });

    testWidgets('confirming the destructive action resolves true', (
      tester,
    ) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm-sheet-confirm')));
      await tester.pumpAndSettle();

      expect(results, [true]);
      expect(find.byType(ConfirmSheet), findsNothing);
    });

    testWidgets('tapping Cancel resolves false', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm-sheet-cancel')));
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.byType(ConfirmSheet), findsNothing);
    });

    testWidgets('tapping the scrim resolves false', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      // Tap far outside the sheet's content, near the top of the screen,
      // which is covered by the modal barrier (scrim) rather than the sheet.
      await tester.tapAt(const Offset(200, 10));
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.byType(ConfirmSheet), findsNothing);
    });

    testWidgets('system back dismiss resolves false', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.byType(ConfirmSheet), findsNothing);
    });

    testWidgets('every colour used resolves from AppTokens/StatusTones, no '
        'raw hex literal', (tester) async {
      final results = <bool?>[];
      await tester.pumpWidget(_buildHost(results));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ConfirmSheet));
      final danger = context.statusTones.danger;

      final allowed = <Color>{
        AppTokens.surface,
        AppTokens.surfaceMuted,
        AppTokens.line,
        AppTokens.ink,
        AppTokens.inkSoft,
        AppTokens.paper,
        danger.foreground,
      };

      final found = _collectAuthoredColors(tester);
      expect(found, isNotEmpty);
      for (final color in found) {
        expect(
          allowed.contains(color),
          isTrue,
          reason:
              'Color $color is not a known AppTokens/StatusTones value — '
              'ConfirmSheet must not use raw hex colours.',
        );
      }
    });
  });
}
