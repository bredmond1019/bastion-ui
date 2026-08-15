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
import '../state/blocked_by_label.dart';
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
                RepoDetailBlockLanes(boardState: boardState),
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

// ---------------------------------------------------------------------------
// RepoDetailBlockLanes — task 4
// ---------------------------------------------------------------------------

/// One [SeverityRow] per block, grouped by lane under an [Eyebrow] label —
/// the replacement for the comma-run paragraph the prose `RepoStatusDto`
/// fields used to force (`BU.13.C` task 4), per the specimen's `cardline`
/// rows (`from-inventory-to-instrument.html` §06).
///
/// Deliberately reads [BoardLaneDto]'s typed lane lists (via
/// [repoBoardProvider]), never the prose `RepoStatusDto.now`/`next`/
/// `blocked` strings — see `RepoDetailStats`'s doc comment for why.
///
/// Every lane renders a group here — task 5 replaced "omit the group when
/// empty" with a real, named empty state per lane ('nothing blocked', etc.)
/// so an empty lane is never a bare gap and never a literal `[]` reaching
/// the screen. `[]` on the dashboard cards was a shipped bug
/// (`BU.ticket.dashboard-now-render`); `repo_detail_empty_test.dart` guards
/// its return here.
class RepoDetailBlockLanes extends StatelessWidget {
  const RepoDetailBlockLanes({super.key, required this.boardState});

  final BriefingSectionState<BoardLaneDto> boardState;

  /// Per-lane empty-state wording. Named per lane rather than a single
  /// generic "nothing here" — the wording is what makes an empty lane
  /// legible instead of just absent.
  static const Map<String, String> _emptyLabels = {
    'now': 'Nothing in progress right now.',
    'next': 'Nothing queued next.',
    'blocked': 'Nothing blocked.',
    'deferred': 'Nothing deferred.',
    'finished': 'Nothing finished yet.',
  };

  @override
  Widget build(BuildContext context) {
    final lanes = boardState.dataOrNull;
    if (lanes == null) {
      // Loading/error already surfaced by RepoDetailStats' em-dash stat
      // row; this section simply has nothing to render yet — an unloaded
      // board is a distinct state from a loaded, empty lane, and only the
      // latter gets the named empty-state treatment below.
      return const SizedBox.shrink();
    }

    final groups = <(String laneId, String label, List<BoardBlockDto> blocks)>[
      ('now', 'Now', lanes.now),
      ('next', 'Next up', lanes.next),
      ('blocked', 'Blocked', lanes.blocked),
      ('deferred', 'Deferred', lanes.deferred),
      ('finished', 'Finished', lanes.finished),
    ];

    return Column(
      key: const ValueKey('repo-detail-block-lanes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (laneId, label, blocks) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Eyebrow(label: label),
          ),
          if (blocks.isEmpty)
            Padding(
              key: ValueKey('repo-detail-lane-empty-$laneId'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _emptyLabels[laneId]!,
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppTokens.inkFaint,
                ),
              ),
            )
          else
            for (final block in blocks) ...[
              _RepoDetailBlockRow(laneId: laneId, block: block),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One block's [SeverityRow]. Title leads; `id` sits secondary, in the meta
/// sub-line rather than the headline. Readiness comes exclusively from
/// [BoardBlockDto.ready] — never derived from `unmetCount == 0` — and a
/// `null` `ready`/`dependentCount` renders as "unknown"/nothing, never a
/// fabricated `false`/`0`.
class _RepoDetailBlockRow extends StatelessWidget {
  const _RepoDetailBlockRow({required this.laneId, required this.block});

  final String laneId;
  final BoardBlockDto block;

  /// The row's severity + trailing pill. The `blocked` lane always reads
  /// as critical regardless of `ready` (a block filed in the blocked lane
  /// is, definitionally, blocked). Outside that lane, `ready` — and only
  /// `ready` — decides: `true` reads calm/on-track, `false` reads warn
  /// (waiting, but not lane-blocked), and `null` (graph data not
  /// available) reads idle/unknown rather than asserting either state.
  (SeverityRowSeverity, StatusPillTone, String) _readiness() {
    if (laneId == 'blocked') {
      return (SeverityRowSeverity.crit, StatusPillTone.blocked, 'BLOCKED');
    }
    return switch (block.ready) {
      true => (SeverityRowSeverity.ok, StatusPillTone.onTrack, 'READY'),
      false => (SeverityRowSeverity.warn, StatusPillTone.inProgress, 'WAITING'),
      null => (SeverityRowSeverity.idle, StatusPillTone.inProgress, 'UNKNOWN'),
    };
  }

  /// The meta sub-line: id (secondary position), wave, readiness wording,
  /// what it waits on (blocked lane only, via task 2's exhaustive label
  /// function), and dependent count — only rendered when NOT null, per
  /// the "null is never a fabricated 0" rule.
  String _meta() {
    final parts = <String>[block.id];

    if (block.wave != null) {
      parts.add('wave ${block.wave}');
    }

    if (laneId == 'blocked') {
      if (block.blockedBy.isNotEmpty) {
        parts.add(blockedByLabel(block.blockedBy.first));
      } else {
        parts.add('blocked');
      }
      if (block.unmetCount != null) {
        parts.add('${block.unmetCount} unmet');
      }
    } else {
      parts.add(switch (block.ready) {
        true => 'ready',
        false => 'not ready',
        null => 'readiness unknown',
      });
    }

    if (block.dependentCount != null) {
      final count = block.dependentCount;
      parts.add('$count block${count == 1 ? '' : 's'} downstream');
    }

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final (severity, pillTone, pillLabel) = _readiness();
    return SeverityRow(
      key: ValueKey('repo-detail-block-row-${block.id}'),
      severity: severity,
      title: block.title,
      pillTone: pillTone,
      pillLabel: pillLabel,
      meta: _meta(),
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
