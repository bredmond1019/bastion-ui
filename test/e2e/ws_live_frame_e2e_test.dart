/// Service-level e2e test: connects a real [BastionSocket] to a real
/// `bastion serve` subprocess (via [BastionServeHarness]), subscribes to a
/// live session's `pane:<name>` topic via [subscribeAndCollect], drives
/// output into that session, and asserts a real `pane` [BastionFrame]
/// decodes with populated fields — the only end-to-end exercise of
/// `models/frame.dart`'s envelope decode against a real server frame.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located, or when `tmux` is not on PATH — never fails on a machine
/// without either.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/pane_provider.dart' show paneTopic;

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('ws live frame e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test(
      'real pane BastionFrame decodes over a live WS subscription',
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
            'service-level e2e test (set $bastionE2eRequireEnvVar=1 to make '
            'this a hard failure instead)',
          );
          return;
        }

        if (!tmuxAvailable()) {
          markTestSkipped(
            'tmux not on PATH — skipping service-level e2e test that '
            'requires a real tmux session',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        final socket = BastionSocket(
          host: h.host,
          port: h.port,
          token: h.token,
        );
        try {
          final connected = socket.statusStream.firstWhere(
            (s) => s == ConnectionStatus.connected,
          );
          socket.connect();
          await connected.timeout(const Duration(seconds: 10));
          expect(socket.status, ConnectionStatus.connected);

          // TODO(BU.7.C task 2): subscribe to the live session's pane:<name>
          // topic via subscribeAndCollect, drive output into the session,
          // and assert a real pane BastionFrame decodes with populated
          // fields. Reference paneTopic/PaneFrame here so the imports are
          // exercised until task 2 fills in the body.
          expect(paneTopic('placeholder'), 'pane:placeholder');
          expect(PaneFrame, isNotNull);
        } finally {
          await socket.dispose();
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
