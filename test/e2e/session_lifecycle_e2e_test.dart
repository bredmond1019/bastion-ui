/// Service-level e2e test: drives the full tmux-backed session REST surface
/// (create → list → pane → send → key → pane → delete → gone) against a
/// real `bastion serve` subprocess (via [BastionServeHarness]), using the
/// app's real, non-mocked [BastionApi].
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located, or when `tmux` is not on PATH — never fails on a machine
/// missing either prerequisite.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('session lifecycle e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test(
      'create -> list -> pane -> send -> key -> pane -> delete -> gone',
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
            'no bastion binary found ($whereChecked) — skipping '
            'session-lifecycle e2e test (set $bastionE2eRequireEnvVar=1 to '
            'make this a hard failure instead)',
          );
          return;
        }

        if (!tmuxAvailable()) {
          markTestSkipped(
            'tmux not on PATH — skipping session-lifecycle e2e test (this '
            'test drives a real tmux-backed session)',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        try {
          await withManagedSession(api, (name) async {
            // (1) The created session appears in the session list.
            final sessionsAfterCreate = await api.getSessions();
            expect(
              sessionsAfterCreate.map((s) => s.name),
              contains(name),
              reason: 'created session "$name" should appear in getSessions',
            );

            // (2) Reading the pane works and exercises the `?lines` param.
            final initialPane = await api.getPane(name, lines: 50);
            expect(initialPane, isA<PaneDto>());
            expect(initialPane.sessionName, name);

            // (3) Drive the session with a literal key sequence + Enter key.
            const marker = 'bastionui-e2e-marker';
            await api.sendKeys(name, 'echo $marker');
            await api.sendKey(name, 'Enter');

            // (4) Bounded poll: wait for the marker to be reflected in the
            // pane output rather than asserting on a single read, since
            // real-process pane output can lag a sent key.
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
                  'expected pane output for "$name" to contain "$marker" '
                  'within $pollTimeout, but it never appeared',
            );

            // (5) Delete the session and confirm it is gone. The
            // withManagedSession `finally` will issue a second, best-effort
            // deleteSession — a harmless no-op — after this callback
            // returns.
            await api.deleteSession(name);
            final sessionsAfterDelete = await api.getSessions();
            expect(
              sessionsAfterDelete.map((s) => s.name),
              isNot(contains(name)),
              reason:
                  'deleted session "$name" should no longer appear in '
                  'getSessions',
            );
          }, name: 'bu7b-session-lifecycle-e2e');
        } finally {
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
