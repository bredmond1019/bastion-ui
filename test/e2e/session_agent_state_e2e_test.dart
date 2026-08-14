/// Service-level e2e test (BU.ticket.session-agent-state task 3): asserts
/// the serve-api v0.26 `agent_state` contract against a REAL `bastion
/// serve` subprocess, on BOTH transports it is documented to ride —
/// `GET /api/sessions` and the `sessions` WebSocket push.
///
/// This deliberately does NOT try to force a specific agent state (e.g.
/// `working` or `blocked`) — driving a real agent into a blocked TUI state
/// is exactly the gap BU.9.E deferred. What this test can honestly assert,
/// and does, is that every session's `agentState` decodes to one of the
/// four contract values (never a parse error, never a thrown exception)
/// on both the REST seed and the live WS snapshot push.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located, or when `tmux` is not on PATH — never fails on a machine
/// missing either prerequisite. Honours `BASTION_E2E_REQUIRE=1` to turn a
/// skip into a hard failure.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

/// The full, closed set of contract values from serve-api.md §10.3 — used
/// to assert `agentState` never decodes to something outside the vocabulary
/// the contract defines.
const _contractStates = {
  AgentState.idle,
  AgentState.working,
  AgentState.blocked,
  AgentState.unknown,
};

void main() {
  group('session agent_state e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      await harness?.stop();
      harness = null;
    });

    test('GET /api/sessions and the sessions WS push both carry a '
        'contract-valid agentState', () async {
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
          'session agent_state e2e (set $bastionE2eRequireEnvVar=1 to '
          'make this a hard failure instead)',
        );
        return;
      }

      if (!tmuxAvailable()) {
        markTestSkipped(
          'tmux not on PATH — skipping session agent_state e2e (needs a '
          'real tmux-backed session)',
        );
        return;
      }

      final api = BastionApi(host: h.host, port: h.port, token: h.token);
      final socket = BastionSocket(host: h.host, port: h.port, token: h.token);
      try {
        await withManagedSession(api, (name) async {
          // --- REST transport -------------------------------------------
          final sessions = await api.getSessions();
          expect(
            sessions.any((s) => s.name == name),
            isTrue,
            reason:
                'expected the created session "$name" to appear in '
                'GET /api/sessions',
          );
          for (final session in sessions) {
            expect(
              _contractStates.contains(session.agentState),
              isTrue,
              reason:
                  'session "${session.name}" agentState '
                  '(${session.agentState}) is outside the four-value '
                  'serve-api v0.26 §10.3 contract vocabulary',
            );
          }

          // --- WebSocket transport ----------------------------------------
          final connected = awaitStatus(
            socket,
            ConnectionStatus.connected,
            timeout: const Duration(seconds: 10),
          );
          socket.connect();
          await connected;
          expect(socket.status, ConnectionStatus.connected);

          final frames = await subscribeAndCollect(
            socket,
            topic: 'sessions',
            count: 1,
            timeout: const Duration(seconds: 20),
          );
          expect(frames, hasLength(1));
          final pushed = frames.single;
          expect(pushed, isA<SessionsFrame>());
          final pushedSessions = (pushed as SessionsFrame).sessions;
          for (final session in pushedSessions) {
            expect(
              _contractStates.contains(session.agentState),
              isTrue,
              reason:
                  'WS-pushed session "${session.name}" agentState '
                  '(${session.agentState}) is outside the four-value '
                  'serve-api v0.26 §10.3 contract vocabulary — decode '
                  'regression on the push path',
            );
          }
        }, name: 'bu-agent-state-e2e');
      } finally {
        await socket.dispose();
        api.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
