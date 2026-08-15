/// Runs screen — live workflow runs, pushed over the `runs` WS topic
/// (`BU.13.E` task 5).
///
/// Watches `state/runs_provider.dart`'s [runsProvider] (REST-seeded,
/// WS-live `List<RunSummaryDto>`) and renders one row per run. Tapping a
/// row drills into that run's per-node snapshot (`GET /api/runs/{id}` via
/// [BastionApi.getRun]) as a VERTICAL node list only — a DAG view is
/// unreadable at phone width and is explicitly out of scope for this block
/// (see `planning/13.E-live-runs/tasks.md`).
///
/// ## Trap 2, made visible: `suspended` reads as live-but-paused
///
/// `run_transition.terminal` is lifecycle-terminal, the OPPOSITE of the
/// engine's own wire-terminal flag (serve-api.md §8.3/§14) — a suspended
/// run reports `status: "suspended", terminal: false` and stays in
/// [runsProvider]'s list. [_RunStatusVisual] gives every wire status both a
/// [StatusTones] tone AND a distinct [IconData] (a non-colour channel), so
/// a suspended run never reads as finished even in grayscale: `suspended`
/// renders in the same live `active` tone as `running`, with a pause icon
/// instead of a play icon, while every finished status (`success`/
/// `failed`/`cancelled`/`budget_halted`) renders in a settled tone with a
/// settled icon.
///
/// ## Trap 3, made visible: `200 []` is a valid empty state
///
/// When the server has no engine mounted, `GET /api/runs` returns `200 []`
/// forever — [_RunsListBody] renders a real, explanatory empty state for an
/// empty list, never an error and never an endless spinner.
///
/// This screen composes the instrument kit (`widgets/instrument/`) and
/// brand primitives only — no new colour tokens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/run_dto.dart';
import '../services/bastion_api.dart';
import '../state/runs_provider.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/instrument/instrument.dart';

/// The tone + icon + label a wire `status` string renders with, resolved
/// once per row so both the run list and the node-drill-in view render
/// identically for the same status value.
class _RunStatusVisual {
  const _RunStatusVisual({
    required this.tone,
    required this.icon,
    required this.label,
    required this.isLive,
  });

  final StatusTone tone;
  final IconData icon;
  final String label;

  /// True for every non-finished status, including `suspended` — see this
  /// file's doc comment, trap 2.
  final bool isLive;

  /// Resolves [status] (a raw wire string — see [RunSummaryDto.status]'s
  /// doc comment on why this is never an enum) to its visual.
  ///
  /// An unrecognised status degrades to a neutral, live-looking badge
  /// carrying the raw text uppercased, rather than throwing — the same
  /// degrade-not-throw posture the DTO layer already uses.
  factory _RunStatusVisual.of(String status, StatusTones tones) {
    switch (status) {
      case 'pending':
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.schedule,
          label: 'PENDING',
          isLive: true,
        );
      case 'running':
        return _RunStatusVisual(
          tone: tones.active,
          icon: Icons.play_circle_fill,
          label: 'RUNNING',
          isLive: true,
        );
      case 'suspended':
        return _RunStatusVisual(
          tone: tones.active,
          icon: Icons.pause_circle_filled,
          label: 'SUSPENDED',
          isLive: true,
        );
      case 'success':
        return _RunStatusVisual(
          tone: tones.success,
          icon: Icons.check_circle,
          label: 'SUCCESS',
          isLive: false,
        );
      case 'failed':
        return _RunStatusVisual(
          tone: tones.danger,
          icon: Icons.error,
          label: 'FAILED',
          isLive: false,
        );
      case 'cancelled':
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.block,
          label: 'CANCELLED',
          isLive: false,
        );
      case 'budget_halted':
        return _RunStatusVisual(
          tone: tones.warning,
          icon: Icons.warning_amber,
          label: 'HALTED',
          isLive: false,
        );
      default:
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.help_outline,
          label: status.isEmpty ? 'UNKNOWN' : status.toUpperCase(),
          isLive: true,
        );
    }
  }
}

/// A small tone+icon+label badge for a run or node status, built from
/// [_RunStatusVisual]. Deliberately not [StatusPill] — [StatusPill] is
/// fixed to four UI-affordance tones (on-track/needs-you/blocked/
/// in-progress) that do not map onto the run/node status vocabulary; this
/// badge draws directly from the ambient [StatusTones] six-tone palette
/// instead, introducing no new colour tokens.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final visual = _RunStatusVisual.of(status, tones);

    final style = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 11,
      color: visual.tone.foreground,
      letterSpacing: 0.6,
    );

    return Container(
      key: ValueKey('status-badge-${status.isEmpty ? 'unknown' : status}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: visual.tone.background,
        border: Border.all(color: visual.tone.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 13, color: visual.tone.foreground),
          const SizedBox(width: 4),
          Text(visual.label, style: style),
        ],
      ),
    );
  }
}

/// Live runs list — REST-seeded and kept current by the `runs` WS topic
/// (`state/runs_provider.dart`). Tapping a run drills into its per-node
/// snapshot; the app bar's back affordance returns to the list.
class RunsScreen extends ConsumerStatefulWidget {
  const RunsScreen({super.key});

  @override
  ConsumerState<RunsScreen> createState() => _RunsScreenState();
}

class _RunsScreenState extends ConsumerState<RunsScreen> {
  /// Captured once, not read from the wall clock inside `build` — feeds
  /// every [AgeChip.since] call on this screen and its drill-in view, per
  /// the pattern `briefing_screen.dart`/`dashboard_screen.dart` already
  /// use.
  late final DateTime _now;

  /// The run currently drilled into, or `null` for the list view.
  String? _selectedRunId;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
  }

  void _open(String runId) => setState(() => _selectedRunId = runId);

  void _closeDetail() => setState(() => _selectedRunId = null);

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRunId;

    if (selected != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('runs-detail-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeDetail,
          ),
          title: const Text('Run'),
        ),
        body: _RunDetailBody(
          runId: selected,
          api: ref.watch(bastionApiProvider)!,
          now: _now,
        ),
      );
    }

    final runs = ref.watch(runsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Runs')),
      body: _RunsListBody(runs: runs, now: _now, onTap: _open),
    );
  }
}

/// The runs-list body: one [Eyebrow] section header, then either the
/// no-engine/no-runs empty state or the scrolling list of run rows.
class _RunsListBody extends StatelessWidget {
  const _RunsListBody({
    required this.runs,
    required this.now,
    required this.onTap,
  });

  final List<RunSummaryDto> runs;
  final DateTime now;
  final void Function(String runId) onTap;

  @override
  Widget build(BuildContext context) {
    final sorted = [...runs]..sort((a, b) => a.runId.compareTo(b.runId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Eyebrow(label: 'Runs'),
        ),
        Expanded(
          child: sorted.isEmpty
              ? const _RunsEmptyState()
              : ListView.builder(
                  key: const ValueKey('runs-list'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final run = sorted[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RunRow(
                        key: ValueKey('run-row-${run.runId}'),
                        run: run,
                        now: now,
                        onTap: () => onTap(run.runId),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Real, explanatory empty state for `GET /api/runs` returning `200 []` —
/// which is always either "no engine mounted" or "nothing running right
/// now", never an error and never a reason to spin forever (trap 3).
class _RunsEmptyState extends StatelessWidget {
  const _RunsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('runs-empty-state'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_outlined, size: 32, color: AppTokens.inkFaint),
            const SizedBox(height: 12),
            Text(
              'No live runs',
              style: AppTypography.textTheme.titleSmall?.copyWith(
                color: AppTokens.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing is running right now, or this server has no engine '
              'mounted. A run started elsewhere appears here as soon as it '
              'starts.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppTokens.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One run row in the list: a [SeverityRow] carrying the run's status
/// badge and age, tappable to drill in.
///
/// The tap affordance itself (the trailing chevron) renders in
/// [AppTokens.accent2] — the same colour token [StatusTones.active] is
/// built from — but is kept separable from the `active`/"running" status
/// signal by shape, not colour: the status is a filled icon inside a
/// bordered pill ([_StatusBadge]), the tap affordance is a bare outline
/// chevron glyph in a fixed neutral position, so the two never read as the
/// same signal even when both happen to render in the same hue.
class _RunRow extends StatelessWidget {
  const _RunRow({super.key, required this.run, required this.now, this.onTap});

  final RunSummaryDto run;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final updatedAt = DateTime.tryParse(run.updatedAt ?? '');
    final metaParts = <String>[
      if (run.specSlug != null && run.specSlug!.isNotEmpty) run.specSlug!,
      run.workflowType ?? 'workflow type pending',
    ];

    return InkWell(
      key: const ValueKey('run-row-tap'),
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: AppTokens.line, width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.runId,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      color: AppTokens.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metaParts.join(' · '),
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppTokens.inkFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatusBadge(status: run.status),
                      const SizedBox(width: 8),
                      if (updatedAt != null) AgeChip.since(updatedAt, now: now),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              key: const ValueKey('run-row-chevron'),
              color: AppTokens.accent2,
            ),
          ],
        ),
      ),
    );
  }
}

/// The drill-in body for one run: fetches `GET /api/runs/{id}` and renders
/// its [NodeTransitionDto]s as a VERTICAL list — never a DAG (out of
/// scope, unreadable at phone width; see this file's doc comment).
class _RunDetailBody extends StatefulWidget {
  const _RunDetailBody({
    required this.runId,
    required this.api,
    required this.now,
  });

  final String runId;
  final BastionApi api;
  final DateTime now;

  @override
  State<_RunDetailBody> createState() => _RunDetailBodyState();
}

class _RunDetailBodyState extends State<_RunDetailBody> {
  late Future<RunStateDto> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getRun(widget.runId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RunStateDto>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            key: ValueKey('run-detail-loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                key: const ValueKey('run-detail-error'),
                'Could not load this run: ${snapshot.error}',
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppTokens.inkFaint,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final run = snapshot.data!;
        if (run.nodes.isEmpty) {
          return Center(
            child: Text(
              key: const ValueKey('run-detail-no-nodes'),
              'No node transitions recorded yet for this run.',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppTokens.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          key: const ValueKey('run-node-list'),
          padding: const EdgeInsets.all(16),
          itemCount: run.nodes.length,
          itemBuilder: (context, index) {
            final node = run.nodes[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NodeRow(
                key: ValueKey('node-row-${node.node}'),
                node: node,
                now: widget.now,
              ),
            );
          },
        );
      },
    );
  }
}

/// One node's row in the vertical node list: name, status badge, and
/// timing — the same [_StatusBadge] the run-list rows use, so a node's
/// status reads with the identical tone/icon vocabulary as its parent
/// run's status.
class _NodeRow extends StatelessWidget {
  const _NodeRow({super.key, required this.node, required this.now});

  final NodeTransitionDto node;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final completedAt = DateTime.tryParse(node.completedAt ?? '');
    final startedAt = DateTime.tryParse(node.startedAt ?? '');
    final ageAnchor = completedAt ?? startedAt;

    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.node,
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    color: AppTokens.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: node.status),
            ],
          ),
          if (ageAnchor != null) ...[
            const SizedBox(height: 8),
            AgeChip.since(ageAnchor, now: now),
          ],
          if (node.error != null && node.error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              node.error!,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: context.statusTones.danger.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
