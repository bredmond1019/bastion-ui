/// Fixture **content** + on-disk **provisioning** for the opt-in
/// fixture-workspace seam used by `test/e2e/bastion_serve_harness.dart`
/// (see that file's `workspaceFixture` param) and
/// `test/e2e/repo_status_e2e_test.dart`.
///
/// This library owns:
///   - The three fixture content constants ([kFixtureStatusMd],
///     [kFixtureHandoffMd], [kFixtureFlowStateJson]), copied verbatim from
///     the sibling `bastion` repo's parser-verified test fixtures
///     (`bastion/src/serve/status/fixtures/status_well_formed.md`,
///     `.../handoff_minimal.md`, `.../flow_state_valid.json`). They are
///     inlined here as Dart string literals rather than read from disk at
///     test time, because the sibling repo's fixture files won't exist on
///     every machine this test suite runs on.
///   - The provisioned fixture repo names ([kFixtureRepoName],
///     [kFixtureRepoNoHandoffName]).
///   - [provisionWorkspaceFixture], which materializes a temp
///     `bastion`-workspace-registry directory (a `[workspaces]`
///     `config.toml` + two fixture repo trees) suitable for pointing a
///     spawned `bastion serve` at via `XDG_CONFIG_HOME=<tmp>`.
///
/// Deliberately has **no** dependency on `bastion_serve_harness.dart` (or
/// any other harness file) — the harness imports this, not the reverse, to
/// avoid an import cycle.
library;

import 'dart:io';

/// Well-formed `planning/status.md` fixture content — copied verbatim from
/// `bastion/src/serve/status/fixtures/status_well_formed.md`. Well-formed
/// OKF frontmatter with `now`/`next`/`blocked` scalars plus a `## Momentum`
/// block.
const String kFixtureStatusMd = '''
---
type: ProjectStatus
title: Fixture Status
description: Well-formed status.md fixture for parse_status tests.
doc_id: fixture-status
layer: [meta]
status: active
updated: 2026-06-30T00:00:00Z
now: "BA.11.D in progress — repo status API"
next: "Wire WS event push"
blocked: []
---

# Status — Fixture

## Momentum

- **now** — BA.11.D in progress — repo status API
- **next** — Wire WS event push
- **blocked** — nothing blocked
- **improve** — tighten parser edge cases
- **recurring** — none yet

## Metrics

- placeholder
''';

/// Minimal `planning/handoff.md` fixture content — copied verbatim from
/// `bastion/src/serve/status/fixtures/handoff_minimal.md`.
const String kFixtureHandoffMd = '''
---
type: Handoff
title: Handoff — minimal fixture
description: Minimal handoff fixture for the read_handoff unit tests.
doc_id: handoff_minimal
layer: [console]
project: bastion
status: active
keywords: [fixture, handoff, test]
related: []
---

# Handoff — minimal fixture

> **For the next agent:** this is a fixture, not a real handoff.

## What we're doing and why

Nothing — this file exists only to exercise `read_handoff` in unit tests.
''';

/// Valid `sdlc-flow-state.json` fixture content — copied verbatim from
/// `bastion/src/serve/status/fixtures/flow_state_valid.json`. Decodes to a
/// `done`-status flow-state with a populated `pr` field.
const String kFixtureFlowStateJson = '''
{
  "spec_slug": "phase6-blockA",
  "branch": "phase6-blockA-flow",
  "started_at": "2026-06-25T18:30:59Z",
  "updated_at": "2026-06-25T19:02:33Z",
  "worktree_path": "~/agentic-portfolio",
  "status": "done",
  "current_task": 5,
  "tasks": {},
  "review": {
    "verdict": "PASS",
    "findings": [],
    "attempts": 1
  },
  "docs": {
    "changed": [],
    "created": []
  },
  "bail_reason": null,
  "pr": {
    "url": "https://github.com/bredmond1019/bastion/pull/1",
    "number": 1
  }
}
''';

/// Name of the fixture repo that has both a `handoff.md` and a
/// `sdlc-flow-state.json` (the "happy path" repo).
const String kFixtureRepoName = 'fixture-repo';

/// Name of the fixture repo that has a `status.md` but deliberately **no**
/// `handoff.md` and **no** flow-state file — this repo drives the
/// `404`→typed-null (`C002`) handoff branch, and an empty-list
/// `getRepoWorkflows` result.
const String kFixtureRepoNoHandoffName = 'fixture-repo-no-handoff';

/// All fixture repo names provisioned by [provisionWorkspaceFixture], in a
/// stable order.
const List<String> kFixtureRepoNames = [
  kFixtureRepoName,
  kFixtureRepoNoHandoffName,
];

/// Provisions a fresh temp directory laid out as a `bastion`
/// `XDG_CONFIG_HOME` root: a `bastion/config.toml` `[workspaces]` registry
/// (mapping [kFixtureRepoName] / [kFixtureRepoNoHandoffName] to absolute
/// repo-root paths under the same temp dir) plus the two fixture repo
/// trees themselves.
///
/// Layout created under the returned `<tmp>`:
///   - `<tmp>/bastion/config.toml`
///   - `<tmp>/repos/fixture-repo/planning/status.md`
///   - `<tmp>/repos/fixture-repo/planning/handoff.md`
///   - `<tmp>/repos/fixture-repo/planning/8A-fixture/sdlc/sdlc-flow-state.json`
///   - `<tmp>/repos/fixture-repo-no-handoff/planning/status.md`
///
/// Callers are responsible for setting `XDG_CONFIG_HOME=<tmp>` on the
/// spawned `bastion serve` child and for deleting `<tmp>` (recursively) on
/// teardown. Pure of any harness dependency — safe to call standalone in a
/// unit test.
Future<Directory> provisionWorkspaceFixture() async {
  final tmp = await Directory.systemTemp.createTemp('bastionui_ws_fixture_');

  final fixtureRepoDir = Directory(
    '${tmp.path}/repos/$kFixtureRepoName',
  ).absolute;
  final noHandoffRepoDir = Directory(
    '${tmp.path}/repos/$kFixtureRepoNoHandoffName',
  ).absolute;

  // fixture-repo: status.md + handoff.md + sdlc-flow-state.json.
  final fixturePlanningDir = Directory('${fixtureRepoDir.path}/planning');
  await fixturePlanningDir.create(recursive: true);
  await File(
    '${fixturePlanningDir.path}/status.md',
  ).writeAsString(kFixtureStatusMd);
  await File(
    '${fixturePlanningDir.path}/handoff.md',
  ).writeAsString(kFixtureHandoffMd);

  final flowStateDir = Directory('${fixturePlanningDir.path}/8A-fixture/sdlc');
  await flowStateDir.create(recursive: true);
  await File(
    '${flowStateDir.path}/sdlc-flow-state.json',
  ).writeAsString(kFixtureFlowStateJson);

  // fixture-repo-no-handoff: status.md only.
  final noHandoffPlanningDir = Directory('${noHandoffRepoDir.path}/planning');
  await noHandoffPlanningDir.create(recursive: true);
  await File(
    '${noHandoffPlanningDir.path}/status.md',
  ).writeAsString(kFixtureStatusMd);

  // The workspace registry `bastion serve` reads from
  // `$XDG_CONFIG_HOME/bastion/config.toml`.
  final configDir = Directory('${tmp.path}/bastion');
  await configDir.create(recursive: true);
  final configToml =
      '[workspaces]\n'
      '$kFixtureRepoName = "${_tomlEscape(fixtureRepoDir.path)}"\n'
      '$kFixtureRepoNoHandoffName = "${_tomlEscape(noHandoffRepoDir.path)}"\n';
  await File('${configDir.path}/config.toml').writeAsString(configToml);

  return tmp;
}

/// Escapes a path for embedding in a TOML basic string: backslashes and
/// double quotes must be escaped. On POSIX this is a no-op for ordinary
/// absolute paths (no backslashes); kept for correctness/portability.
String _tomlEscape(String path) =>
    path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
