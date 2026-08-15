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
///
/// Re-skinned in `BU.10.C` task 4: the status table and workflow list now
/// render inside a [PanelCard] each, section labels use [Eyebrow], and the
/// screen's display heading (the repo name) wears a [HeadingRule]
/// underneath (budget rule: one per screen). Every status-field row already
/// guarded against the `[]` empty-collection sentinel
/// (`RepoStatusDto`'s field parsers) — that guard is unchanged here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/board_dto.dart';
import '../models/repo_status_dto.dart';
import '../state/briefing_model.dart';
import '../state/repo_board_provider.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../state/workflows_provider.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/instrument/instrument.dart';
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
    final boardState = ref.watch(repoBoardProvider(repoName));

    return Scaffold(
      appBar: AppBar(title: Text(repoName)),
      body: workflowsState.loading && status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _RepoDetailHeading(repoName: repoName),
                const SizedBox(height: 16),
                RepoDetailStats(boardState: boardState),
                const SizedBox(height: 16),
                if (status != null) _StatusTable(status: status),
                if (status != null && status.hasHandoff) ...[
                  const SizedBox(height: 16),
                  _HandoffSection(repoName: repoName),
                ],
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Eyebrow(label: 'Workflows'),
                ),
                if (workflowsState.workflows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No workflows',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppTokens.inkFaint,
                      ),
                    ),
                  )
                else
                  PanelCard(
                    child: Column(
                      children: [
                        for (final (i, w) in workflowsState.workflows.indexed)
                          WorkflowProgress(
                            // Indexed rather than keyed on `specSlug` alone:
                            // two workflow rows can legitimately share a
                            // spec slug (a re-run), and this list renders as
                            // direct children of one `Column` (unlike the
                            // pre-brand `ListView.children`), so sibling
                            // keys must be unique within a single build, not
                            // just distinct-looking.
                            key: ValueKey(
                              'workflow-progress-row-${w.specSlug}-$i',
                            ),
                            workflow: w,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// This screen's display heading — the repo name — with one [HeadingRule]
/// underneath, per the block's budget rule (one per screen).
class _RepoDetailHeading extends StatelessWidget {
  const _RepoDetailHeading({required this.repoName});

  final String repoName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          repoName,
          style: AppTypography.textTheme.headlineSmall?.copyWith(
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        const HeadingRule(),
      ],
    );
  }
}

/// The repo detail's `now`/`next`/`blocked` stat row — three [StatTile]s
/// drawn from [repoBoardProvider]'s typed lane counts (`BU.13.C` task 3),
/// per the specimen's `bignum` row (`from-inventory-to-instrument.html`
/// §06).
///
/// Deliberately reads lane **lengths**, never `RepoStatusDto.now`/`next`/
/// `blocked` — those are narrative prose and can disagree with the typed
/// records (that disagreement is the whole reason this block exists).
///
/// A plain [StatelessWidget] over an already-resolved
/// `BriefingSectionState<BoardLaneDto>`, mirroring `briefing_screen.dart`'s
/// `BriefingHeader` — testable with a bare fixture, no Riverpod/HTTP
/// wiring required.
class RepoDetailStats extends StatelessWidget {
  const RepoDetailStats({super.key, required this.boardState});

  final BriefingSectionState<BoardLaneDto> boardState;

  /// A loading or errored board renders an em dash, never a fabricated
  /// `"0"` — the count is unknown, not zero.
  static String _format(int? count) => count == null ? '—' : '$count';

  @override
  Widget build(BuildContext context) {
    final lanes = boardState.dataOrNull;
    final unknown = lanes == null;
    final blockedCount = unknown ? null : lanes.blocked.length;

    return IntrinsicHeight(
      key: const ValueKey('repo-detail-stats'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(
              value: _format(unknown ? null : lanes.now.length),
              label: 'now',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: _format(unknown ? null : lanes.next.length),
              label: 'next',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: _format(blockedCount),
              label: 'blocked',
              // Calm at zero ("nothing blocked" is reassurance, not an
              // alert) and critical when there is something waiting.
              // Unknown (loading/error) also stays neutral — the tone
              // itself must never assert "danger" from a fact the app
              // does not have.
              severity: (blockedCount != null && blockedCount > 0)
                  ? StatTileSeverity.danger
                  : StatTileSeverity.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

/// The parsed `now`/`next`/`blocked`/momentum status fields, rendered as a
/// simple label/value table inside a [PanelCard].
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

    return PanelCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: const ValueKey('repo-status-table'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Eyebrow(label: 'Status'),
            ),
            for (final (label, value) in rows)
              if (value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.textTheme.labelSmall?.copyWith(
                          color: AppTokens.inkSoft,
                        ),
                      ),
                      Text(
                        value,
                        style: AppTypography.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Handoff title + markdown body, fetched via [repoHandoffProvider], shown
/// inside a [PanelCard].
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
        return PanelCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const ValueKey('repo-handoff-section'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Eyebrow(label: 'Handoff'),
                ),
                Text(
                  info.title,
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    color: AppTokens.ink,
                  ),
                ),
                const SizedBox(height: 8),
                MarkdownView(data: info.body),
              ],
            ),
          ),
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
