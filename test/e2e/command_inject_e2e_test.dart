/// Service-level e2e test (BU.9.C): drives the `POST /api/actions/command`
/// **inject** SUCCESS path against a real `bastion serve` subprocess —
/// injecting a shell command into an existing live session, asserting the
/// returned session id, and confirming the command actually landed by polling
/// the session's pane for its output.
///
/// Existing e2e coverage only exercises inject *failure* (404/C002 against a
/// non-existent session, in `workflow_events_e2e_test.dart`) and *spawn*
/// success — the inject success round-trip (the returned-id contract plus the
/// command reaching the pane) was previously unproven end-to-end. Inject sends
/// `command` as literal keystrokes + Enter (serve-api §12.2), so a plain shell
/// `echo` is observable without a runnable `claude` binary.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`, which
/// requires a built `bastion` binary. Self-skips (via `markTestSkipped`) when
/// no `bastion` binary can be located, or when `tmux` is not on PATH.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('command inject success e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test(
      'inject into a live session returns its id and lands in the pane',
      () async {
        harness = await BastionServeHarness.start();
        final h = harness;
        if (h == null) {
          const whereChecked =
              'checked BASTION_BIN, ../bastion/target/release/bastion, '
              '../bastion/target/debug/bastion';
          if (bastionE2eRequireBinary()) {
            fail(
              '$bastionE2eRequireEnvVar is set but no bastion binary could '
              'be located ($whereChecked) — build one with '
              '`cargo build -p bastion` in ../bastion, or set BASTION_BIN.',
            );
          }
          markTestSkipped(
            'no bastion binary found ($whereChecked) — skipping inject '
            'success e2e (set $bastionE2eRequireEnvVar=1 to make this a hard '
            'failure instead)',
          );
          return;
        }

        if (!tmuxAvailable()) {
          markTestSkipped(
            'tmux not on PATH — skipping inject success e2e (needs a real '
            'tmux-backed session)',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        try {
          await withManagedSession(api, (name) async {
            const marker = 'bu9c-inject-success-marker';

            // Inject a shell command into the existing session. §12.1: the
            // response `session` is the target (existing) session id.
            final returned = await api.postCommand(
              CommandRequest(
                mode: CommandMode.inject,
                session: name,
                command: 'echo $marker',
              ),
            );
            expect(
              returned,
              name,
              reason:
                  'inject-mode postCommand must return the target session id',
            );

            // Confirm the injected command actually landed: bounded poll of
            // the pane for the echoed marker (real-process output can lag).
            const pollTimeout = Duration(seconds: 15);
            const pollInterval = Duration(milliseconds: 500);
            final deadline = DateTime.now().add(pollTimeout);
            var found = false;
            while (DateTime.now().isBefore(deadline)) {
              final pane = await api.getPane(name);
              if (pane.lines.any((line) => line.contains(marker))) {
                found = true;
                break;
              }
              await Future<void>.delayed(pollInterval);
            }
            expect(
              found,
              isTrue,
              reason:
                  'expected injected command output "$marker" to appear in '
                  'session "$name" pane within $pollTimeout, but it never did',
            );
          }, name: 'bu9c-inject-success-e2e');
        } finally {
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
