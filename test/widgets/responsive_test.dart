import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:bastion_ui/widgets/responsive_scaffold.dart';

Widget _atWidth(double width, {required Widget child}) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 1200)),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  const list = SizedBox(key: ValueKey('list'), width: 10, height: 10);
  const detail = SizedBox(key: ValueKey('detail'), width: 10, height: 10);

  group('ResponsiveScaffold', () {
    testWidgets('phone width (< breakpoint) shows only the list', (t) async {
      await t.pumpWidget(
        _atWidth(
          400,
          child: const ResponsiveScaffold(list: list, detail: detail),
        ),
      );
      expect(find.byKey(const ValueKey('list')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail')), findsNothing);
      // Phone presentation: the lockup rides in a real AppBar.
      expect(find.byType(BastielLockup), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('tablet width (>= breakpoint) shows list and detail', (
      t,
    ) async {
      await t.pumpWidget(
        _atWidth(
          900,
          child: const ResponsiveScaffold(list: list, detail: detail),
        ),
      );
      expect(find.byKey(const ValueKey('list')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail')), findsOneWidget);
      final divider = t.widget<VerticalDivider>(find.byType(VerticalDivider));
      expect(divider.color, AppTokens.line);

      final listGround = t.widget<ColoredBox>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('list')),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(listGround.color, AppTokens.surface);

      // Tablet presentation: the lockup is the rail's header, above `list`.
      expect(find.byType(BastielLockup), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.byKey(const ValueKey('list')),
                matching: find.byType(ColoredBox),
              )
              .first,
          matching: find.byType(BastielLockup),
        ),
        findsOneWidget,
      );
    });

    testWidgets('isWide reflects the breakpoint', (t) async {
      await t.pumpWidget(
        _atWidth(
          900,
          child: Builder(
            builder: (context) {
              expect(ResponsiveScaffold.isWide(context), isTrue);
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });
}
