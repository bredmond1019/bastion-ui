/// Service-level e2e test (BU.9.B): drives the real [sessionsProvider] /
/// [SessionsNotifier] against a real `bastion serve` subprocess and asserts a
/// session created via REST propagates into the notifier's state via a
/// server-pushed `sessions` WebSocket snapshot.
///
/// This is the provider-level counterpart to `ws_live_frame_e2e_test.dart`
/// (which decodes a raw `pane` frame): it exercises the full app path — REST
/// seed on construction, the `"sessions"` topic subscription, the 150ms
/// debounce, the `SessionsFrame` snapshot-replace, and the `_sawWsSnapshot`
/// ordering guard — none of which is covered end-to-end elsewhere (the
/// provider's logic is otherwise only unit-tested against a fake socket).
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`, which
/// requires a built `bastion` binary. Self-skips (via `markTestSkipped`) when
/// no `bastion` binary can be located, or when `tmux` is not on PATH.
@Tags(['e2e'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('sessions provider live-frame e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test('a created session propagates into sessionsProvider via a pushed '
        'SessionsFrame', () async {
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
          'no bastion binary found ($whereChecked) — skipping sessions '
          'provider live-frame e2e (set $bastionE2eRequireEnvVar=1 to make '
          'this a hard failure instead)',
        );
        return;
      }

      if (!tmuxAvailable()) {
        markTestSkipped(
          'tmux not on PATH — skipping sessions provider live-frame e2e '
          '(needs a real tmux-backed session)',
        );
        return;
      }

      final api = BastionApi(host: h.host, port: h.port, token: h.token);
      final socket = BastionSocket(host: h.host, port: h.port, token: h.token);
      final container = ProviderContainer();
      try {
        // Connect FIRST, then wire the providers — mirroring the real app
        // shell's order (main.dart), so the notifier subscribes to the
        // `"sessions"` topic while the socket is already connected (a
        // `send()` on a disconnected socket only registers the topic, it
        // does not transmit, and the first connect never replays).
        final connected = awaitStatus(
          socket,
          ConnectionStatus.connected,
          timeout: const Duration(seconds: 10),
        );
        socket.connect();
        await connected;
        expect(socket.status, ConnectionStatus.connected);

        container.read(bastionSocketProvider.notifier).state = socket;
        container.read(bastionApiProvider.notifier).state = api;

        // Keep the provider alive (and mounted) for the duration so it is
        // not disposed between polls; building it constructs the notifier,
        // which seeds via REST and subscribes to `"sessions"`.
        final listenerSub = container.listen(
          sessionsProvider,
          (previous, next) {},
          fireImmediately: true,
        );

        await withManagedSession(api, (name) async {
          // The server's sessions poller pushes a full snapshot every
          // ~2s to `"sessions"` subscribers; after the 150ms debounce the
          // notifier replaces its state with that snapshot. Poll the
          // provider until the created session shows up.
          const pollTimeout = Duration(seconds: 20);
          const pollInterval = Duration(milliseconds: 250);
          final deadline = DateTime.now().add(pollTimeout);
          var found = false;
          while (DateTime.now().isBefore(deadline)) {
            final sessions = container.read(sessionsProvider);
            if (sessions.any((s) => s.name == name)) {
              found = true;
              break;
            }
            await Future<void>.delayed(pollInterval);
          }
          expect(
            found,
            isTrue,
            reason:
                'expected sessionsProvider to reflect created session '
                '"$name" via a pushed SessionsFrame within $pollTimeout, '
                'but it never appeared',
          );
        }, name: 'bu9b-sessions-provider-e2e');

        listenerSub.close();
      } finally {
        container.dispose();
        await socket.dispose();
        api.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
