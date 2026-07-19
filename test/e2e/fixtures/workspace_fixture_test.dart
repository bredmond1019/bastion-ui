/// Gating unit tests for [provisionWorkspaceFixture]. Deliberately NOT
/// tagged `e2e` — this file spawns no `bastion serve` subprocess; it only
/// exercises on-disk provisioning of the fixture workspace registry, so it
/// runs as part of the normal gating suite (`flutter test --exclude-tags
/// e2e`). The read surface against a real server is covered by the
/// `e2e`-tagged `repo_status_e2e_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'workspace_fixture.dart';

void main() {
  group('provisionWorkspaceFixture', () {
    Directory? tmp;

    tearDown(() async {
      final d = tmp;
      tmp = null;
      if (d != null && await d.exists()) {
        await d.delete(recursive: true);
      }
    });

    test('creates a fresh, distinct temp dir per call', () async {
      final a = await provisionWorkspaceFixture();
      final b = await provisionWorkspaceFixture();
      tmp = a;
      addTearDown(() async {
        if (await b.exists()) {
          await b.delete(recursive: true);
        }
      });

      expect(await a.exists(), isTrue);
      expect(await b.exists(), isTrue);
      expect(a.path, isNot(equals(b.path)));
    });

    test(
      'writes fixture-repo status.md, handoff.md, and flow-state json',
      () async {
        tmp = await provisionWorkspaceFixture();
        final repoDir = Directory('${tmp!.path}/repos/$kFixtureRepoName');

        final status = File('${repoDir.path}/planning/status.md');
        final handoff = File('${repoDir.path}/planning/handoff.md');
        final flowState = File(
          '${repoDir.path}/planning/8A-fixture/sdlc/sdlc-flow-state.json',
        );

        expect(await status.exists(), isTrue);
        expect(await status.readAsString(), kFixtureStatusMd);
        expect(await handoff.exists(), isTrue);
        expect(await handoff.readAsString(), kFixtureHandoffMd);
        expect(await flowState.exists(), isTrue);
        expect(await flowState.readAsString(), kFixtureFlowStateJson);

        // Flow-state content is valid, parseable JSON with the expected
        // shape (spec_slug / status / pr), not just non-empty text.
        final decoded =
            jsonDecode(await flowState.readAsString()) as Map<String, dynamic>;
        expect(decoded['spec_slug'], 'phase6-blockA');
        expect(decoded['status'], 'done');
        expect(decoded['pr'], isNotNull);
      },
    );

    test(
      'writes fixture-repo-no-handoff status.md only (no handoff, no flow-state)',
      () async {
        tmp = await provisionWorkspaceFixture();
        final repoDir = Directory(
          '${tmp!.path}/repos/$kFixtureRepoNoHandoffName',
        );

        expect(
          await File('${repoDir.path}/planning/status.md').exists(),
          isTrue,
        );
        expect(
          await File('${repoDir.path}/planning/handoff.md').exists(),
          isFalse,
        );
        expect(await Directory('${repoDir.path}/planning').list().toList(), [
          predicate<FileSystemEntity>(
            (e) => e.path.endsWith('status.md'),
            'only status.md',
          ),
        ]);
      },
    );

    test(
      'writes a bastion/config.toml [workspaces] table with absolute repo paths',
      () async {
        tmp = await provisionWorkspaceFixture();
        final configFile = File('${tmp!.path}/bastion/config.toml');
        expect(await configFile.exists(), isTrue);

        final contents = await configFile.readAsString();
        expect(contents, contains('[workspaces]'));

        final fixtureRepoAbsPath = Directory(
          '${tmp!.path}/repos/$kFixtureRepoName',
        ).absolute.path;
        final noHandoffAbsPath = Directory(
          '${tmp!.path}/repos/$kFixtureRepoNoHandoffName',
        ).absolute.path;

        expect(contents, contains('$kFixtureRepoName = "$fixtureRepoAbsPath"'));
        expect(
          contents,
          contains('$kFixtureRepoNoHandoffName = "$noHandoffAbsPath"'),
        );
        // Both registered paths must be absolute (start with '/' on POSIX).
        expect(fixtureRepoAbsPath.startsWith('/'), isTrue);
        expect(noHandoffAbsPath.startsWith('/'), isTrue);
      },
    );
  });

  test('kFixtureRepoNames lists both provisioned repo names in order', () {
    expect(kFixtureRepoNames, [kFixtureRepoName, kFixtureRepoNoHandoffName]);
  });
}
