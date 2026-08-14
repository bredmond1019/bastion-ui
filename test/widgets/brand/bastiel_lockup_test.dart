// Widget test for BastielLockup (ticket-brand-header-lockup task 1).
//
// Pins three things: (a) both images resolve without a runtime asset error,
// (b) the rendered icon is 32x32 and the wordmark is 22dp tall, and (c) the
// merged semantics of the subtree contain exactly one label, and it is
// "bastiel" -- the accessibility contract the ticket is explicit is the
// point, not decoration.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/widgets/brand/brand.dart';

Widget _buildLockup() {
  return const MaterialApp(home: Scaffold(body: BastielLockup()));
}

void main() {
  group('BastielLockup', () {
    testWidgets('both images resolve without a runtime asset error', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLockup());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('icon renders 32x32 and wordmark renders 22dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLockup());
      await tester.pumpAndSettle();

      final images = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(BastielLockup),
              matching: find.byType(Image),
            ),
          )
          .toList();

      expect(images, hasLength(2));

      final icon = images[0];
      expect(icon.width, 32);
      expect(icon.height, 32);

      final wordmark = images[1];
      expect(wordmark.height, 22);
      // Width is derived from the 344x64 source aspect ratio at a 22dp
      // render height: 22 * 344 / 64 ~= 118.25dp.
      expect(wordmark.width, closeTo(118.25, 0.01));
    });

    testWidgets('exposes exactly one accessible name, "bastiel" -- the icon '
        'contributes no label', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(_buildLockup());
      await tester.pumpAndSettle();

      final mergedSemantics = tester.getSemantics(find.byType(BastielLockup));

      // Collect every non-empty label anywhere in the subtree.
      final labels = <String>[];
      void visit(SemanticsNode node) {
        if (node.label.isNotEmpty) {
          labels.add(node.label);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(mergedSemantics);

      expect(labels, equals(['bastiel']));

      semanticsHandle.dispose();
    });
  });
}
