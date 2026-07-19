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

import 'package:flutter_test/flutter_test.dart';

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
}
