/// Service-level e2e test: boots a real `bastion serve` subprocess (via
/// [BastionServeHarness]) and drives the app's real, non-mocked
/// [BastionApi] / [BastionSocket] against it, to catch wire-contract drift
/// between BastionUI's Dart DTOs and `bastion`'s `serve-api.md`.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located — never fails on a machine without one built.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/models/dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

import 'bastion_serve_harness.dart';

/// [BastionSocket.dispose] awaits the transport's close, which for a
/// socket that never completed its handshake (e.g. a fatal-auth 401
/// during connect) can hang indefinitely on the underlying
/// `IOWebSocketChannel.sink.close()`. Bound it here so a harness/transport
/// quirk can't hang the whole e2e run — this is test-robustness, not a
/// change to the production dispose() contract.
Future<void> _disposeBounded(BastionSocket socket) =>
    socket.dispose().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );

void main() {
  group('serve contract e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test(
      'real BastionApi/BastionSocket against a real bastion serve',
      () async {
        harness = await BastionServeHarness.start();
        final h = harness;
        if (h == null) {
          markTestSkipped(
            'no bastion binary found (checked BASTION_BIN, '
            '../bastion/target/release/bastion, '
            '../bastion/target/debug/bastion) — skipping service-level '
            'e2e test',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        try {
          // --- Health: primary drift canary for the base envelope --------
          final health = await api.getHealth();
          expect(health, isA<HealthDto>());

          // --- Authed reads decode against the real DTOs (empty is OK) ---
          final sessions = await api.getSessions();
          expect(sessions, isA<List>());

          final repos = await api.getRepos();
          expect(repos, isA<List>());

          // --- Write-path envelope (best-effort) --------------------------
          // Use `inject` against a session name that cannot exist, so the
          // server responds quickly (404/C002 per serve-api.md §12.3)
          // instead of attempting a real tmux/agent spawn. The response
          // must decode to either a success session-id string or a typed
          // ApiError — we don't depend on the command itself succeeding,
          // only that the request/response envelope shape holds.
          try {
            final sessionId = await api.postCommand(
              const CommandRequest(
                mode: CommandMode.inject,
                session: 'e2e-contract-test-nonexistent-session',
                command: '/status',
              ),
            );
            expect(sessionId, isA<String>());
          } on ApiError catch (e) {
            // A typed ApiError is an acceptable outcome — the envelope
            // shape held even though the command itself did not succeed.
            expect(e.statusCode, greaterThanOrEqualTo(400));
          } on FatalAuthError catch (_) {
            fail(
              'postCommand with the correct token must not surface a '
              'fatal-auth error',
            );
          }
        } finally {
          api.dispose();
        }

        // --- WS handshake: real connect() reaches connected -------------
        final socket = BastionSocket(host: h.host, port: h.port, token: h.token);
        try {
          final connected = socket.statusStream.firstWhere(
            (s) => s == ConnectionStatus.connected,
          );
          socket.connect();
          await connected.timeout(const Duration(seconds: 10));
          expect(socket.status, ConnectionStatus.connected);
        } finally {
          await _disposeBounded(socket);
        }

        // --- Fatal auth (401): wrong token yields typed fatal-auth ------
        final wrongTokenSocket = BastionSocket(
          host: h.host,
          port: h.port,
          token: bastionServeHarnessWrongToken,
        );
        try {
          final disconnectedAfterAuthFailure = wrongTokenSocket.statusStream
              .firstWhere((s) => s == ConnectionStatus.disconnected);
          wrongTokenSocket.connect();
          await disconnectedAfterAuthFailure.timeout(
            const Duration(seconds: 10),
          );
          expect(wrongTokenSocket.isFatalAuth, isTrue);
        } finally {
          await _disposeBounded(wrongTokenSocket);
        }

        final wrongTokenApi = BastionApi(
          host: h.host,
          port: h.port,
          token: bastionServeHarnessWrongToken,
        );
        try {
          await expectLater(
            wrongTokenApi.getSessions(),
            throwsA(isA<FatalAuthError>()),
          );
        } finally {
          wrongTokenApi.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
