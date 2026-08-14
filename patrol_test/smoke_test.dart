// Patrol smoke test: drives BastionUI against a real `bastion serve` on an
// Android emulator (reachable via 10.0.2.2) and asserts each screen actually
// renders live backend data (real tmux sessions + real repo registry).
//
// Spike per planning/decisions — not wired into the harness.json gating
// suite; run manually with:
//   patrol test -t patrol_test/smoke_test.dart -d <device>
// Requires a live `bastion serve --token <token>` reachable from the
// emulator and at least one repo/tmux session for non-empty screens.
//
// Screenshotting is done separately via `adb exec-out screencap` — Patrol
// 4.x's binding (LiveTestWidgetsFlutterBinding-based) does not expose
// integration_test's takeScreenshot(), so this test focuses on functional
// assertions instead.
library;

import 'package:bastion_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

// Android emulator's alias for the host machine's loopback interface.
const _serveHost = '10.0.2.2';
const _serveToken = 'patrol-smoke-token';

void main() {
  patrolTest('smoke: connect, tour every tab, and open a session', ($) async {
    await $.pumpWidgetAndSettle(const ProviderScope(child: BastionApp()));
    expect($('Configure a connection in Settings'), findsOneWidget);

    // ---- Settings: configure + connect ----
    await $(Icons.settings).tap();
    await $.pumpAndSettle();
    expect($('Connection Settings'), findsOneWidget);

    // Settings form order: host, port (defaults to 4317, left alone), token.
    await $(TextFormField).at(0).enterText(_serveHost);
    await $(TextFormField).at(2).enterText(_serveToken);

    await $(FilledButton).tap();
    await $.pumpAndSettle();
    expect($('Settings saved'), findsOneWidget);

    await $(Icons.arrow_back).tap();
    // Give the socket a moment to connect over the real network.
    await $.pump(const Duration(seconds: 2));
    await $.pumpAndSettle(timeout: const Duration(seconds: 10));

    // ---- Sessions tab (default) — real tmux sessions from bastion serve ----
    expect($(Icons.list), findsWidgets);
    final sessionTiles = $(ListTile);
    expect(
      sessionTiles.evaluate().isNotEmpty,
      isTrue,
      reason: 'expected at least one real tmux session to render',
    );
    await sessionTiles.at(0).tap();
    await $.pumpAndSettle(timeout: const Duration(seconds: 5));
    await $(Icons.arrow_back).tap();
    await $.pumpAndSettle();

    // ---- Dashboard tab — real repo registry from bastion serve ----
    await $(Icons.dashboard).tap();
    await $.pumpAndSettle(timeout: const Duration(seconds: 5));
    final repoTiles = $(ListTile);
    expect(
      repoTiles.evaluate().isNotEmpty,
      isTrue,
      reason: 'expected at least one real repo to render',
    );
    await repoTiles.at(0).tap();
    await $.pumpAndSettle(timeout: const Duration(seconds: 5));
    await $(Icons.arrow_back).tap();
    await $.pumpAndSettle();

    // ---- Actions (quick commands) tab ----
    await $(Icons.flash_on).tap();
    await $.pumpAndSettle();
    expect($('Quick Actions'), findsOneWidget);

    await $(Icons.add).tap();
    await $.pumpAndSettle();
    expect($('Add command'), findsOneWidget);
  });
}
