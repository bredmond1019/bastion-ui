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
          // TODO(BU.7.B task 2): fill in the lifecycle body — wrap in
          // withManagedSession(api, (name) async { ... },
          // name: 'bu7b-session-lifecycle-e2e') and drive
          // createSession -> getSessions -> getPane -> sendKeys/sendKey ->
          // getPane (bounded poll) -> deleteSession -> getSessions.
        } finally {
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
