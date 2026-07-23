import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(find.byType(VerticalDivider), findsOneWidget);
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
