// Widget smoke test for the BastionUI root app shell.
//
// Verifies that the app boots, the ProviderScope is wired, and the
// placeholder home screen renders without errors.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/main.dart';

void main() {
  testWidgets('BastionApp boots with ProviderScope and renders home', (
    WidgetTester tester,
  ) async {
    // ProviderScope wraps BastionApp as it does in main().
    await tester.pumpWidget(const ProviderScope(child: BastionApp()));

    // The placeholder home scaffold should render without error.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('BastionUI'), findsOneWidget);
  });
}
