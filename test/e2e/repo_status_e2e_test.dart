/// Service-level e2e test: boots a real `bastion serve` subprocess with an
/// opt-in fixture workspace (via [BastionServeHarness.start]'s
/// `workspaceFixture` param) and drives the app's real, non-mocked
/// [BastionApi] repo read-surface against it — `GET /api/repos`,
/// `/api/repos/{name}/status`, `/handoff`, `/workflows` — to catch
/// repo/workflow DTO drift end-to-end, including the `404`→typed-null
/// (`C002`) handoff branch.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`,
/// which requires a built `bastion` binary (see `planning/harness.json`).
///
/// Self-skips (via `markTestSkipped`) when no `bastion` binary can be
/// located — never fails on a machine without one built. No tmux is
/// required for this block (the repo routes shell no tmux), so there is no
/// `tmuxAvailable()` guard here, only the binary-absent skip.
@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import 'bastion_serve_harness.dart';
import 'fixtures/workspace_fixture.dart';

void main() {
  group('repo read-surface e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess (or fixture temp dir) is left
      // behind even if an assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test(
      'real BastionApi repo/status/workflows/handoff against a real bastion serve',
      () async {
        harness = await BastionServeHarness.start(workspaceFixture: true);
        final h = harness;
        if (h == null) {
          markTestSkipped(
            'bastion binary not found — skipping repo read-surface e2e',
          );
          return;
        }

        final api = BastionApi(host: h.host, port: h.port, token: h.token);
        try {
          // --- GET /api/repos: both fixture repos are listed ------------
          final repos = await api.getRepos();
          final repoNames = repos.map((r) => r.name).toSet();
          expect(repoNames, contains(kFixtureRepoName));
          expect(repoNames, contains(kFixtureRepoNoHandoffName));

          // --- GET /api/repos/{name}/status: decodes, key field set -----
          final status = await api.getRepoStatus(kFixtureRepoName);
          expect(status, isA<RepoStatusDto>());
          expect(status.now, isNotEmpty);

          // --- GET /api/repos/{name}/workflows: non-empty, decodes ------
          final flows = await api.getRepoWorkflows(kFixtureRepoName);
          expect(flows, isNotEmpty);
          final flow = flows.first;
          expect(flow.specSlug, isNotEmpty);
          expect(flow.status, isNotEmpty);

          // --- GET /api/repos/{name}/handoff: present → typed non-null --
          final present = await api.getRepoHandoff(kFixtureRepoName);
          expect(present, isNotNull);
          expect(present, isA<HandoffInfo>());

          // --- GET /api/repos/{name}/handoff: absent → typed null -------
          // (the 404/C002 branch — the core drift target for this block)
          final absent = await api.getRepoHandoff(kFixtureRepoNoHandoffName);
          expect(absent, isNull);
        } finally {
          api.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
