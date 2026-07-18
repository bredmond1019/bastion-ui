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

          await withManagedSession(api, (name) async {
            // (1) Kick off the collector — do NOT await yet — so it is
            // listening before any output is produced by the drive step
            // below. This avoids a subscribe-then-listen race.
            final collected = subscribeAndCollect(
              socket,
              topic: paneTopic(name),
              count: 1,
              timeout: const Duration(seconds: 20),
            );

            // (2) Drive output into the session so a `pane` frame is
            // pushed.
            await api.sendKeys(name, 'echo bastionui-ws-e2e-marker');
            await api.sendKey(name, 'Enter');

            // (3) Await the collected frame(s).
            final frames = await collected;
            expect(frames, isNotEmpty);
            expect(frames.first, isA<PaneFrame>());

            // (4) Assert the envelope decoded with populated fields.
            final frame = frames.first as PaneFrame;
            expect(frame.session, name);
            expect(frame.seq, isA<int>());
            expect(frame.seq, greaterThanOrEqualTo(0));
            expect(frame.lines, isA<List<String>>());
          }, name: 'bu7c-ws-live-frame-e2e');
        } finally {
          await socket.dispose();
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
