// Regression test for `BU.ticket.dashboard-now-render` Task 3 — a repo whose
// `now` arrives as the empty-collection sentinel (already normalised to `''`
// by `RepoSummaryDto.fromJson`, see `repo_status_dto.dart`) must render NO
// subtitle text on the Dashboard, not the literal string `[]` and not a
// blank placeholder line. A repo with a real `now` value must still show it.
//
// Mirrors the override style established by `test/widgets/dashboard_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/state/repos_provider.dart';
import 'package:bastion_ui/state/workflows_provider.dart';

class _FakeRepoListNotifier extends StateNotifier<List<RepoSummaryDto>>
    implements RepoListNotifier {
  _FakeRepoListNotifier(super.state);

  @override
  Future<void> refresh() async {}
}

class _FakeRepoWorkflowsNotifier extends StateNotifier<RepoWorkflowsState>
    implements RepoWorkflowsNotifier {
  _FakeRepoWorkflowsNotifier(super.state, {required this.repoName});

  @override
  final String repoName;
}

Widget _buildScreen({required List<RepoSummaryDto> repos}) {
  final overrides = <Override>[
    reposProvider.overrideWith((ref) => _FakeRepoListNotifier(repos)),
  ];

  for (final repo in repos) {
    overrides.add(
      repoWorkflowsProvider(repo.name).overrideWith(
        (ref) => _FakeRepoWorkflowsNotifier(
          const RepoWorkflowsState(loading: false),
          repoName: repo.name,
        ),
      ),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: DashboardScreen()),
  );
}

void main() {
  group('DashboardScreen empty now', () {
    testWidgets(
      'a repo whose now normalises to empty renders no subtitle text, '
      'and never the literal "[]"',
      (tester) async {
        // `RepoSummaryDto.fromJson` already normalises the `"[]"` sentinel
        // to `''` (Task 2) — construct the DTO the way the app actually
        // receives it, off the wire.
        final emptyNowRepo = RepoSummaryDto.fromJson(const {
          'name': 'alpha',
          'now': '[]',
          'has_handoff': false,
        });
        const normalRepo = RepoSummaryDto(
          name: 'beta',
          now: 'shipping task 4',
          hasHandoff: false,
        );

        await tester.pumpWidget(
          _buildScreen(repos: [emptyNowRepo, normalRepo]),
        );
        await tester.pump();

        // The regression this ticket exists to prevent: the literal
        // sentinel text must never appear anywhere on screen.
        expect(find.text('[]'), findsNothing);

        // alpha (empty now) has no subtitle Text widget at all.
        final alphaTile = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('alpha'),
            matching: find.byType(ListTile),
          ),
        );
        expect(alphaTile.subtitle, isNull);

        // beta (real now) still renders its subtitle text.
        expect(find.text('shipping task 4'), findsOneWidget);
        final betaTile = tester.widget<ListTile>(
          find.ancestor(of: find.text('beta'), matching: find.byType(ListTile)),
        );
        expect(betaTile.subtitle, isNotNull);
      },
    );
  });
}
