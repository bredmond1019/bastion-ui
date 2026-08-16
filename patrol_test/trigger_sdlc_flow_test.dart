// Patrol-driven trigger: connect to a real `bastion serve`, add a
// command-palette entry for `/sdlc-flow ticket-e2e-fixed-timeouts`, and fire
// it in spawn mode — proving the phone can kick off a real SDLC pipeline run,
// not just read state.
//
// Manual, non-gating (mirrors patrol_test/smoke_test.dart's role) — run with:
//   patrol test -t patrol_test/trigger_sdlc_flow_test.dart -d <device>
// Requires a live `bastion serve --token <token>` reachable from the emulator.
//
// Sets the invoke sheet's spawn Directory explicitly to this repo's absolute
// path — left blank on the first run of this test (2026-08-15), the spawned
// session launched `claude` in `bastion serve`'s own cwd (the HQ root)
// instead of this repo, so `/sdlc-flow ticket-e2e-fixed-timeouts` could never
// have found its spec even if delivered.
//
// Known upstream gap (`bastion` `BA.ticket.spawn-command-delivery-race`):
// spawn's readiness signal can race Claude's own TUI startup, silently
// dropping the triggering command. This test only asserts the phone-side
// mechanics (no inline invoke error, spawn accepted) — it cannot itself
// prove the command landed in the pane; verify that separately (`tmux
// capture-pane`) until that ticket lands.
library;

import 'package:bastion_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

const _serveHost = '10.0.2.2';
const _serveToken = 'patrol-smoke-token';
const _label = 'SDLC: e2e-fixed-timeouts';
const _command = '/sdlc-flow ticket-e2e-fixed-timeouts';
const _spawnName = 'phone-triggered-e2e-fixed-timeouts';
const _spawnDir = '/Users/brandon/Dev/agentic-portfolio/core/bastion-ui';

void main() {
  patrolTest('trigger sdlc-flow ticket-e2e-fixed-timeouts via spawn', (
    $,
  ) async {
    await $.pumpWidgetAndSettle(const ProviderScope(child: BastionApp()));

    // ---- Connect (idempotent: configure if not already connected) ----
    if ($('Configure a connection in Settings').evaluate().isNotEmpty) {
      await $(Icons.settings).tap();
      await $.pumpAndSettle();
      await $(TextFormField).at(0).enterText(_serveHost);
      await $(TextFormField).at(2).enterText(_serveToken);
      await $(FilledButton).tap();
      await $.pumpAndSettle();
      await $(Icons.arrow_back).tap();
      await $.pump(const Duration(seconds: 2));
      await $.pumpAndSettle(timeout: const Duration(seconds: 10));
    }

    // ---- Actions tab ----
    await $(Icons.flash_on).tap();
    await $.pumpAndSettle();
    expect($('Quick Actions'), findsOneWidget);

    // ---- Add the palette entry (if not already present from a prior run) ----
    if ($(_label).evaluate().isEmpty) {
      await $(const Key('command-add-button')).tap();
      await $.pumpAndSettle();
      expect($('Add command'), findsOneWidget);
      await $(const Key('command-dialog-label')).enterText(_label);
      await $(const Key('command-dialog-command')).enterText(_command);
      await $(const Key('command-dialog-save')).tap();
      await $.pumpAndSettle();
    }
    expect($(_label), findsOneWidget);

    // ---- Fire it: tap the tile, switch to Spawn, name it, Run ----
    await $(_label).tap();
    await $.pumpAndSettle();
    expect($(_command), findsWidgets);

    await $('Spawn').tap();
    await $.pumpAndSettle();
    await $(const Key('command-invoke-name')).enterText(_spawnName);
    await $(const Key('command-invoke-dir')).enterText(_spawnDir);
    await $.pumpAndSettle();

    await $(const Key('command-invoke-button')).tap();
    // Spawn waits on server-side readiness — can legitimately take a while.
    await $.pumpAndSettle(timeout: const Duration(seconds: 60));

    // Success pops the sheet and navigates to the new session's detail
    // screen; a failure leaves the sheet open with an inline error instead.
    expect(
      $(const Key('command-invoke-error')).evaluate(),
      isEmpty,
      reason: 'spawn should not surface an inline invoke error',
    );
  });
}
