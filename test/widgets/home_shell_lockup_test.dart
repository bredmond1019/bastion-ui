import 'package:bastion_ui/main.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the bastiel lockup to the app bar the operator actually sees.
///
/// `ticket-brand-header-lockup` originally put the lockup in
/// `ResponsiveScaffold`, which is used as a `body:` — so on a phone it
/// rendered *below* `HomeShell`'s real AppBar (two stacked bars on the
/// Sessions tab) and did not render at all on Dashboard or Actions, which
/// do not use that widget. Every gate passed; only a device capture showed
/// the app bar still reading "BastionUI" as plain text.
///
/// That is the same failure mode as `BU.1.A` (built, but not on the path
/// that renders), which this repo has now hit twice. This test exists so it
/// cannot happen a third time silently: it asserts the lockup is reachable
/// from `HomeShell`'s AppBar specifically, not merely present somewhere in
/// the tree.
void main() {
  testWidgets('HomeShell renders the bastiel lockup in its AppBar', (t) async {
    await t.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeShell())),
    );
    await t.pump();

    final appBar = find.byType(AppBar);
    expect(appBar, findsOneWidget, reason: 'HomeShell owns exactly one AppBar');

    expect(
      find.descendant(of: appBar, matching: find.byType(BastielLockup)),
      findsOneWidget,
      reason: 'the lockup must be IN the always-visible AppBar, not elsewhere',
    );

    // The plain-text title it replaced must be gone — otherwise both could
    // coexist and the regression would be invisible again.
    expect(
      find.descendant(of: appBar, matching: find.text('BastionUI')),
      findsNothing,
    );
  });

  testWidgets('the lockup exposes exactly one accessible name', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeShell())),
    );
    await t.pump();

    // The icon is decorative (ExcludeSemantics) and the wordmark owns the
    // name — ported from bastion-web's wordmark.tsx, whose comment is
    // explicit that assistive tech should announce "bastiel" once, not twice.
    expect(find.bySemanticsLabel('bastiel'), findsOneWidget);
    handle.dispose();
  });
}
