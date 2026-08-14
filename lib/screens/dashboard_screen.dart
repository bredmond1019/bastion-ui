/// Dashboard screen — one row per workspace-registry repo with its
/// current-focus line and a status badge (in-flight workflow / pending
/// handoff / idle).
///
/// Watches `repos_provider.dart`'s [reposProvider] for the repo list; each
/// row additionally watches `workflows_provider.dart`'s
/// [repoWorkflowsProvider] (keyed by repo name) to derive its in-flight
/// state — the same family provider that auto-refetches on a matching
/// `workflow_done` WS event (per `workflows_provider.dart`'s
/// `RepoWorkflowsNotifier`), so a row's in-flight badge clears without a
/// manual refresh once that repo's refetched workflow list reports no
/// `running` entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/repo_status_dto.dart';
import '../state/repos_provider.dart';
import '../state/workflows_provider.dart';
import '../widgets/status_badge.dart';

/// The WS/REST status string that marks a workflow as currently running
/// (serve-api v0.3 §11.3).
const _runningWorkflowStatus = 'running';

/// Route-name helper for a repo's detail screen (`BU.2.A` Task 5).
///
/// Kept here (rather than importing a not-yet-existing detail screen) so
/// this file can be implemented and tested independently of Task 5 — mirrors
/// `sessions_list_screen.dart`'s `sessionDetailRouteName` pattern. Task 7
/// registers the matching route in `main.dart`.
String repoDetailRouteName(String repoName) => '/repos/$repoName';

/// Live dashboard — one row per workspace-registry repo, sorted by name for
/// a stable display order.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repos = ref.watch(reposProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: repos.isEmpty
          ? const Center(child: Text('No repos registered'))
          : RefreshIndicator(
              onRefresh: () => ref.read(reposProvider.notifier).refresh(),
              child: _DashboardListView(repos: repos),
            ),
    );
  }
}

class _DashboardListView extends StatelessWidget {
  const _DashboardListView({required this.repos});

  final List<RepoSummaryDto> repos;

  @override
  Widget build(BuildContext context) {
    final sorted = [...repos]..sort((a, b) => a.name.compareTo(b.name));

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final repo = sorted[index];
        return _RepoRow(key: ValueKey(repo.name), repo: repo);
      },
    );
  }
}

/// One dashboard row — watches [repoWorkflowsProvider] keyed by
/// [repo.name] to derive the in-flight badge state, independent of every
/// other row.
class _RepoRow extends ConsumerWidget {
  const _RepoRow({super.key, required this.repo});

  final RepoSummaryDto repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflows = ref.watch(repoWorkflowsProvider(repo.name));
    final inFlight = workflows.workflows.any(
      (w) => w.status == _runningWorkflowStatus,
    );

    final state = inFlight
        ? RepoBadgeState.inFlight
        : (repo.hasHandoff ? RepoBadgeState.hasHandoff : RepoBadgeState.idle);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: () =>
            Navigator.of(context).pushNamed(repoDetailRouteName(repo.name)),
        title: Text(repo.name),
        subtitle: repo.now.isNotEmpty
            ? Text(repo.now, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: StatusBadge(state: state),
      ),
    );
  }
}
