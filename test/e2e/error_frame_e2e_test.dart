/// Service-level e2e test (BU.9.E): asserts the client decodes a REAL server
/// `error` frame. Sending a `subscribe` for an unknown topic deterministically
/// elicits `{"kind":"error","payload":{"code":"WS_ERR",...}}` from
/// `bastion serve` (serve-api §7.8), which `models/frame.dart` must decode into
/// a typed [ErrorFrame]. The error-frame decode path is otherwise never
/// exercised against a real server.
///
/// This is protocol-level — no tmux is required (the error is produced by the
/// WS classifier before any session I/O), so it self-skips only on a missing
/// `bastion` binary.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`, which
/// requires a built `bastion` binary.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('error frame decode e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test('a bad-topic subscribe elicits a real WS_ERR ErrorFrame', () async {
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
          'no bastion binary found ($whereChecked) — skipping error-frame '
          'e2e (set $bastionE2eRequireEnvVar=1 to make this a hard failure '
          'instead)',
        );
        return;
      }

      final socket = BastionSocket(host: h.host, port: h.port, token: h.token);
      try {
        final connected = awaitStatus(
          socket,
          ConnectionStatus.connected,
          timeout: const Duration(seconds: 10),
        );
        socket.connect();
        await connected;
        expect(socket.status, ConnectionStatus.connected);

        // Arm the collector BEFORE sending the bad frame (subscribe-before-
        // trigger discipline), then send a subscribe for a topic that is
        // neither "sessions" nor "pane:<name>" — the server classifies it as
        // an unknown/malformed topic and returns an `error` frame.
        final collected = collectFrames(
          socket,
          match: (f) => f is ErrorFrame,
          timeout: const Duration(seconds: 10),
        );
        socket.send(const {
          'kind': 'subscribe',
          'payload': {'topic': 'bu9e-bogus-topic'},
        });

        final frames = await collected;
        expect(frames, isNotEmpty);
        expect(frames.first, isA<ErrorFrame>());
        final error = frames.first as ErrorFrame;
        expect(
          error.payload.code,
          'WS_ERR',
          reason: 'serve-api §7.8: WS error frames carry code "WS_ERR"',
        );
        expect(error.payload.message, isNotNull);
      } finally {
        await socket.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
