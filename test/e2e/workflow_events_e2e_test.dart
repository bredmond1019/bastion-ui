/// Service-level e2e test: boots a real `bastion serve` subprocess with an
/// opt-in fixture workspace (via [BastionServeHarness.start]'s
/// `workspaceFixture` param) and asserts the `event{workflow_done}` WS push
/// (`bastion` PR #21 — `FlowWatcher` wired into the `Hub` interval poller)
/// decodes end-to-end when a fixture repo's `sdlc-flow-state.json`
/// transitions from a non-terminal to a terminal `status`.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary from CURRENT `bastion` main (the
/// workflow_done push landed in PR #21 — a stale prebuilt binary lacks it).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located — never fails on a machine without one built. The
/// workflow_done poller shells no tmux, so no `tmuxAvailable()` guard is
/// needed for this group.
@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

import 'bastion_serve_harness.dart';
import 'e2e_support.dart';

void main() {
  group('workflow_done event push e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess (or fixture temp dir) is left
      // behind even if an assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test('transitioning a fixture repo to terminal status broadcasts '
        'event{workflow_done}', () async {
      harness = await BastionServeHarness.start(workspaceFixture: true);
      final h = harness;
      if (h == null) {
        markTestSkipped(
          'bastion binary not found — skipping workflow_done e2e',
        );
        return;
      }

      final socket = BastionSocket(host: h.host, port: h.port, token: h.token);
      try {
        final connected = socket.statusStream.firstWhere(
          (s) => s == ConnectionStatus.connected,
        );
        socket.connect();
        await connected.timeout(const Duration(seconds: 10));
        expect(socket.status, ConnectionStatus.connected);

        // Use a FRESH spec-slug — NOT the pre-provisioned `8A-fixture`
        // flow, which ships terminal status:"done" at startup and would
        // never fire a transition event.
        const specSlug = '8B-workflow-done';
        final repo = h.fixtureRepos.first;
        final planningDir = h.fixtureRepoPlanningDir(repo);

        // Seed non-terminal.
        await writeFixtureFlowState(
          planningDir,
          specSlug: specSlug,
          status: 'running',
        );

        // Let the server's poll cycle record the baseline before we
        // transition — FlowWatcher's first observation emits no event
        // (this ordering is load-bearing per bastion's poll.rs). Default
        // BASTION_POLL_INTERVAL is 2s; wait ~2+ intervals.
        await Future<void>.delayed(const Duration(seconds: 5));

        // Register the collector BEFORE triggering the transition so no
        // frame is lost to a race.
        final done = collectEvents(
          socket,
          event: 'workflow_done',
          timeout: const Duration(seconds: 60),
        );

        // Transition to terminal.
        await writeFixtureFlowState(
          planningDir,
          specSlug: specSlug,
          status: 'done',
          pr: 'https://example/pr/1',
        );

        final frames = await done;
        final frame = frames.single;
        expect(frame.event, 'workflow_done');
        expect(frame.extra['repo'], repo);
        expect(frame.extra['spec_slug'], specSlug);
        expect(frame.extra['status'], 'done');
      } finally {
        await socket.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('command round-trip e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test('spawn-mode postCommand round-trips through getSessions', () async {
      harness = await BastionServeHarness.start();
      final h = harness;
      if (h == null) {
        markTestSkipped(
          'bastion binary not found — skipping spawn round-trip e2e',
        );
        return;
      }

      if (!tmuxAvailable()) {
        markTestSkipped('tmux not available — skipping spawn round-trip e2e');
        return;
      }

      final api = BastionApi(host: h.host, port: h.port, token: h.token);
      String? sessionId;
      try {
        try {
          sessionId = await api.postCommand(
            const CommandRequest(
              mode: CommandMode.spawn,
              name: '8b-spawn-roundtrip',
              command: '/status',
              model: CommandModel.sonnet,
            ),
          );
        } on ApiError catch (e) {
          // Readiness (§12.3 `504`/`C007`) is an environment property (a
          // runnable `claude` binary), not a contract property — self-skip
          // on that specific failure rather than hard-failing.
          Map<String, dynamic>? body;
          try {
            body = jsonDecode(e.body) as Map<String, dynamic>;
          } catch (_) {
            body = null;
          }
          if (e.statusCode == 504 && body?['code'] == 'C007') {
            markTestSkipped(
              'spawn readiness timed out (no runnable claude in this '
              'environment) — skipping spawn round-trip e2e',
            );
            return;
          }
          rethrow;
        }

        expect(sessionId, isNotEmpty);

        final sessions = await api.getSessions();
        expect(sessions.map((s) => s.name), contains(sessionId));
      } finally {
        if (sessionId != null && sessionId.isNotEmpty) {
          try {
            await api.deleteSession(sessionId);
          } catch (_) {
            // Best-effort cleanup — never let a teardown failure mask the
            // real result or the original error.
          }
        }
        api.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('inject-mode postCommand against an unknown session yields '
        '404/C002 per §12.3', () async {
      harness = await BastionServeHarness.start();
      final h = harness;
      if (h == null) {
        markTestSkipped(
          'bastion binary not found — skipping tightened inject '
          'assertion e2e',
        );
        return;
      }

      if (!tmuxAvailable()) {
        markTestSkipped(
          'tmux not on PATH — skipping tightened inject assertion e2e (the '
          '404/C002 unknown-session path needs a running tmux server)',
        );
        return;
      }

      final api = BastionApi(host: h.host, port: h.port, token: h.token);
      try {
        // Create a real session first so a tmux server is definitely running.
        // Injecting into a DIFFERENT, non-existent session then exercises the
        // documented "session not found" path (§12.3 → 404/C002); without a
        // running server, tmux reports "no server running", a distinct stderr
        // the server maps to 500/C010 — so this guard session is what makes
        // the 404/C002 assertion deterministic.
        await withManagedSession(api, (_) async {
          try {
            await api.postCommand(
              const CommandRequest(
                mode: CommandMode.inject,
                session: '8b-inject-nonexistent-session',
                command: '/status',
              ),
            );
            fail('expected postCommand to throw ApiError');
          } on ApiError catch (e) {
            expect(e.statusCode, 404);
            final body = jsonDecode(e.body) as Map<String, dynamic>;
            expect(body['code'], 'C002');
          }
        }, name: 'bu8b-inject-guard-session');
      } finally {
        api.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
