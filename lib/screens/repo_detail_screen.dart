/// Repo-detail screen — parsed status table, `handoff.md` body (when
/// present), and per-workflow progress rows for a single workspace-registry
/// repo.
///
/// Watches `workflows_provider.dart`'s [repoWorkflowsProvider] (keyed by the
/// routed repo name) for the parsed [RepoStatusDto] + [WorkflowStateDto]
/// list — the same family provider `dashboard_screen.dart` watches, and the
/// one that auto-refetches on a matching `workflow_done` WS event.
///
/// `RepoStatusDto.hasHandoff` only says *whether* a handoff exists — the
/// title/body come from a separate `GET /api/repos/{name}/handoff` call, not
/// covered by `workflows_provider.dart`'s Task 3 fetch. [repoHandoffProvider]
/// (a `FutureProvider.family`, local to this file) makes that call directly
/// through the shared `bastionApiProvider`, only when `hasHandoff` is true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/repo_status_dto.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../state/workflows_provider.dart';
import '../widgets/markdown_view.dart';
import '../widgets/workflow_progress.dart';

/// The `handoff.md` for a single repo, fetched on demand (only watched by
/// [RepoDetailScreen] when the repo's status reports `has_handoff: true`).
///
/// Mirrors the null-means-absent contract of
/// `BastionApi.getRepoHandoff` (404 / `C002`) — a `null` resolved value is a
/// legitimate "no handoff" result, not an error.
final repoHandoffProvider = FutureProvider.family<HandoffInfo?, String>((
  ref,
  repoName,
) {
  final api = ref.watch(bastionApiProvider);
  if (api == null) {
    throw StateError(
      'repoHandoffProvider read before bastionApiProvider was set — the app '
      'shell must connect before mounting the repo-detail screen.',
    );
  }
  return api.getRepoHandoff(repoName);
});

/// Status table + handoff + workflow-progress view for a single repo.
class RepoDetailScreen extends ConsumerWidget {
  const RepoDetailScreen({super.key, required this.repoName});

  /// The repo this screen is showing (route argument from
  /// `dashboard_screen.dart`'s `repoDetailRouteName`).
  final String repoName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsState = ref.watch(repoWorkflowsProvider(repoName));
    final status = workflowsState.status;

    return Scaffold(
      appBar: AppBar(title: Text(repoName)),
      body: workflowsState.loading && status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (status != null) _StatusTable(status: status),
                if (status != null && status.hasHandoff) ...[
                  const SizedBox(height: 16),
                  _HandoffSection(repoName: repoName),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Workflows',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (workflowsState.workflows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No workflows'),
                  )
                else
                  ...workflowsState.workflows.map(
                    (w) => WorkflowProgress(
                      key: ValueKey('workflow-progress-row-${w.specSlug}'),
                      workflow: w,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The parsed `now`/`next`/`blocked`/momentum status fields, rendered as a
/// simple label/value table.
class _StatusTable extends StatelessWidget {
  const _StatusTable({required this.status});

  final RepoStatusDto status;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Now', status.now),
      ('Next', status.next),
      ('Blocked', status.blocked),
      ('Momentum — now', status.momentumNow),
      ('Momentum — next', status.momentumNext),
      ('Momentum — blocked', status.momentumBlocked),
      ('Momentum — improve', status.momentumImprove),
      ('Momentum — recurring', status.momentumRecurring),
    ];

    return Column(
      key: const ValueKey('repo-status-table'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          if (value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Text(value),
                ],
              ),
            ),
      ],
    );
  }
}

/// Handoff title + markdown body, fetched via [repoHandoffProvider].
///
/// The caller only mounts this widget when `status.hasHandoff` is true, but
/// [repoHandoffProvider] can still legitimately resolve `null` (a race
/// between the status flag and a since-cleared handoff) — that case renders
/// nothing, matching "omit without error".
class _HandoffSection extends ConsumerWidget {
  const _HandoffSection({required this.repoName});

  final String repoName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handoff = ref.watch(repoHandoffProvider(repoName));

    return handoff.when(
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        return Column(
          key: const ValueKey('repo-handoff-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            MarkdownView(data: info.body),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
