// Widget tests for DashboardScreen + StatusBadge.
//
// Overrides `reposProvider` and (per-repo) `repoWorkflowsProvider` directly
// with fake StateNotifiers (no real socket/API involved) so these tests
// exercise only the rendering + badge logic — mirrors the override style
// established by `sessions_list_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/state/repos_provider.dart';
import 'package:bastion_ui/state/workflows_provider.dart';
import 'package:bastion_ui/widgets/status_badge.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

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

  /// Simulates what `RepoWorkflowsNotifier._onEvent` does when a matching
  /// `workflow_done` event triggers a refetch: replace the workflow list
  /// with one that no longer reports a `running` entry.
  void markDone(List<WorkflowStateDto> refreshedWorkflows) {
    state = state.copyWith(workflows: refreshedWorkflows, loading: false);
  }
}

WorkflowStateDto _workflow({required String status}) => WorkflowStateDto(
  specSlug: '2.A-dashboard-repo-detail',
  branch: '2.A-dashboard-repo-detail-flow',
  status: status,
  currentTask: 4,
  startedAt: '2026-07-02T10:00:00Z',
  updatedAt: '2026-07-02T10:15:00Z',
);

Widget _buildScreen({
  required List<RepoSummaryDto> repos,
  Map<String, RepoWorkflowsState> workflowsByRepo = const {},
  Map<String, _FakeRepoWorkflowsNotifier>? capturedNotifiers,
}) {
  final overrides = <Override>[
    reposProvider.overrideWith((ref) => _FakeRepoListNotifier(repos)),
  ];

  for (final repo in repos) {
    final notifier = _FakeRepoWorkflowsNotifier(
      workflowsByRepo[repo.name] ?? const RepoWorkflowsState(loading: false),
      repoName: repo.name,
    );
    capturedNotifiers?[repo.name] = notifier;
    overrides.add(
      repoWorkflowsProvider(repo.name).overrideWith((ref) => notifier),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: DashboardScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen', () {
    testWidgets('renders one row per repo with the correct badges', (
      tester,
    ) async {
      const repos = [
        RepoSummaryDto(
          name: 'alpha',
          now: 'shipping task 4',
          hasHandoff: false,
        ),
        RepoSummaryDto(name: 'beta', now: 'idle', hasHandoff: true),
      ];

      await tester.pumpWidget(
        _buildScreen(
          repos: repos,
          workflowsByRepo: {
            'alpha': RepoWorkflowsState(
              workflows: [_workflow(status: 'running')],
              loading: false,
            ),
          },
        ),
      );
      await tester.pump();

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.byType(StatusBadge), findsNWidgets(2));
      // alpha has a running workflow -> in-flight badge.
      expect(find.byIcon(Icons.autorenew), findsOneWidget);
      // beta has no running workflow but has_handoff -> handoff badge.
      expect(find.byIcon(Icons.assignment_late), findsOneWidget);
    });

    testWidgets('shows empty state when there are no repos', (tester) async {
      await tester.pumpWidget(_buildScreen(repos: const []));
      await tester.pump();

      expect(find.byType(StatusBadge), findsNothing);
      expect(find.text('No repos registered'), findsOneWidget);
    });

    testWidgets('idle repo with no handoff shows the idle badge', (
      tester,
    ) async {
      const repos = [
        RepoSummaryDto(
          name: 'gamma',
          now: 'nothing in flight',
          hasHandoff: false,
        ),
      ];

      await tester.pumpWidget(_buildScreen(repos: repos));
      await tester.pump();

      expect(find.byIcon(Icons.autorenew), findsNothing);
      expect(find.byIcon(Icons.assignment_late), findsNothing);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets(
      'in-flight badge clears when a mocked workflow_done event fires '
      'for that repo',
      (tester) async {
        const repos = [
          RepoSummaryDto(
            name: 'alpha',
            now: 'shipping task 4',
            hasHandoff: false,
          ),
        ];
        final captured = <String, _FakeRepoWorkflowsNotifier>{};

        await tester.pumpWidget(
          _buildScreen(
            repos: repos,
            workflowsByRepo: {
              'alpha': RepoWorkflowsState(
                workflows: [_workflow(status: 'running')],
                loading: false,
              ),
            },
            capturedNotifiers: captured,
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.autorenew), findsOneWidget);

        // Simulate the `workflow_done` event triggering a refetch that
        // reports the workflow as no longer running.
        captured['alpha']!.markDone([_workflow(status: 'done')]);
        await tester.pump();

        expect(find.byIcon(Icons.autorenew), findsNothing);
      },
    );

    testWidgets('tapping a row navigates toward the repo detail route', (
      tester,
    ) async {
      const repos = [
        RepoSummaryDto(
          name: 'alpha',
          now: 'shipping task 4',
          hasHandoff: false,
        ),
      ];
      String? pushedRoute;

      final overrides = <Override>[
        reposProvider.overrideWith((ref) => _FakeRepoListNotifier(repos)),
        repoWorkflowsProvider('alpha').overrideWith(
          (ref) => _FakeRepoWorkflowsNotifier(
            const RepoWorkflowsState(loading: false),
            repoName: 'alpha',
          ),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: const DashboardScreen(),
            onGenerateRoute: (settings) {
              pushedRoute = settings.name;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('detail')),
              );
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      expect(pushedRoute, repoDetailRouteName('alpha'));
    });
  });
}
