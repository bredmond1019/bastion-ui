/// Service-level e2e test (BU.9.D): exercises the client's reconnect
/// resilience (the BU.0.A-ccf behaviour) against a REAL `bastion serve` — the
/// backoff reconnect, the resubscribe-registry replay, and recovery to
/// `connected` after a genuine connection drop. All of this is otherwise only
/// unit-tested with a fake socket (`reconnect_test.dart`,
/// `reconnect_resubscribe_test.dart`).
///
/// The server has no in-band drop signal, so the drop is forced by
/// [BastionServeHarness.restart] (kill + respawn on the SAME port). After the
/// socket recovers, a fresh `sessions` snapshot arriving proves the client
/// replayed its `"sessions"` subscription onto the new connection (the new
/// server assigns a fresh connection id with no subscriptions, so no snapshot
/// would arrive unless the replay fired).
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`, which
/// requires a built `bastion` binary. Self-skips (via `markTestSkipped`) when
/// no `bastion` binary can be located, or when `tmux` is not on PATH.
@Tags(['e2e'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('reconnect resilience e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test(
      'socket recovers and replays its subscription after a real server drop',
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
            'no bastion binary found ($whereChecked) — skipping reconnect '
            'e2e (set $bastionE2eRequireEnvVar=1 to make this a hard failure '
            'instead)',
          );
          return;
        }

        if (!tmuxAvailable()) {
          markTestSkipped(
            'tmux not on PATH — skipping reconnect e2e (subscribes to the '
            'sessions topic, which the server backs with tmux)',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        final socket = BastionSocket(
          host: h.host,
          port: h.port,
          token: h.token,
        );
        bool matchesSessions(BastionFrame f) => f is SessionsFrame;
        try {
          final connected = awaitStatus(
            socket,
            ConnectionStatus.connected,
            timeout: const Duration(seconds: 10),
          );
          socket.connect();
          await connected;
          expect(socket.status, ConnectionStatus.connected);

          // A managed session guarantees the tmux server is running (so the
          // sessions poller pushes real snapshots) and survives the restart
          // (tmux is a separate daemon, unaffected by killing bastion serve).
          await withManagedSession(api, (name) async {
            // Subscribe to `sessions` via the real socket path so the topic
            // lands in the resubscribe registry that reconnect must replay.
            socket.send(ClientFrames.subscribe('sessions'));

            // Baseline: a snapshot arrives on the live (pre-drop) connection.
            final before = await collectFrames(
              socket,
              match: matchesSessions,
              timeout: const Duration(seconds: 15),
            );
            expect(before, isNotEmpty);

            // Arm a recovery watcher BEFORE forcing the drop: complete once we
            // observe `connected` that follows a reconnecting/connecting
            // transition (i.e. a real drop-and-recover cycle, not the initial
            // connect).
            final recovered = Completer<void>();
            var sawDrop = false;
            final recSub = socket.statusStream.listen((s) {
              if (s == ConnectionStatus.reconnecting ||
                  s == ConnectionStatus.connecting) {
                sawDrop = true;
              }
              if (s == ConnectionStatus.connected &&
                  sawDrop &&
                  !recovered.isCompleted) {
                recovered.complete();
              }
            });

            // Force a real drop: kill + respawn bastion serve on the same port.
            await h.restart();

            await recovered.future.timeout(const Duration(seconds: 120));
            await recSub.cancel();
            expect(socket.status, ConnectionStatus.connected);
            expect(
              socket.isFatalAuth,
              isFalse,
              reason: 'a transient drop must not be treated as fatal auth',
            );

            // Prove live data resumes: a fresh snapshot on the NEW connection
            // can only arrive if the `sessions` subscription was replayed.
            final after = await collectFrames(
              socket,
              match: matchesSessions,
              timeout: const Duration(seconds: 15),
            );
            expect(after, isNotEmpty);
            expect(after.first, isA<SessionsFrame>());
          }, name: 'bu9d-reconnect-e2e');
        } finally {
          await socket.dispose();
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );
  });
}
