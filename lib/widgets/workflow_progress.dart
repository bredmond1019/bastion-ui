/// Per-workflow progress row for `repo_detail_screen.dart` — one row per
/// entry from `GET /api/repos/{name}/workflows` (serve-api v0.3 §11.3).
///
/// Renders `spec_slug`, task index vs. `status`, and `branch` as plain text.
/// No PR link: `WorkflowStateDto` exposes no `pr_url` field on the current
/// contract — see `planning/2.A-dashboard-repo-detail/tasks.md` Context
/// Pointers / Notes for the tracked contract gap.
///
/// Re-skinned in `BU.10.C` task 4: the leading dot's colour is derived from
/// the ambient [StatusTones] extension via `Theme.of(context)`, never a raw
/// colour literal. `WorkflowStateDto.status` is a free-form string (no
/// closed vocabulary on the wire contract), so [_toneFor] classifies it by
/// substring rather than an exhaustive `switch` — an unrecognised status
/// falls back to `tones.neutral` instead of throwing.
library;

import 'package:flutter/material.dart';

import '../models/repo_status_dto.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// A single workflow's progress — spec slug, current task, status, branch.
class WorkflowProgress extends StatelessWidget {
  const WorkflowProgress({super.key, required this.workflow});

  /// The workflow this row renders.
  final WorkflowStateDto workflow;

  /// Classifies [workflow.status] onto one of the [StatusTones] members.
  /// `running`/`in_progress`-shaped statuses read as [StatusTones.info],
  /// `done`/`complete`/`success`-shaped statuses read as
  /// [StatusTones.success], `failed`/`error`/`blocked`-shaped statuses read
  /// as [StatusTones.danger], and anything else falls back to
  /// [StatusTones.neutral].
  StatusTone _toneFor(StatusTones tones) {
    final normalized = workflow.status.toLowerCase();
    if (normalized.contains('running') || normalized.contains('progress')) {
      return tones.info;
    }
    if (normalized.contains('done') ||
        normalized.contains('complete') ||
        normalized.contains('success')) {
      return tones.success;
    }
    if (normalized.contains('fail') ||
        normalized.contains('error') ||
        normalized.contains('block')) {
      return tones.danger;
    }
    return tones.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(context.statusTones);

    // The caller (`repo_detail_screen.dart`) wraps its workflow list in a
    // `PanelCard`, whose ground is an opaque `DecoratedBox` — `ListTile`
    // paints on the nearest `Material` ancestor, which would otherwise sit
    // behind the panel and get clipped invisible. A transparent `Material`
    // gives this row its own paint surface without adding a second
    // background colour.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey('workflow-progress-${workflow.specSlug}'),
        leading: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.foreground,
          ),
        ),
        title: Text(
          workflow.specSlug,
          style: AppTypography.textTheme.titleSmall?.copyWith(
            color: AppTokens.ink,
          ),
        ),
        isThreeLine: true,
        subtitle: Text(
          'task ${workflow.currentTask} — ${workflow.status}\n'
          'branch: ${workflow.branch}',
          style: AppTypography.mono.copyWith(color: AppTokens.inkSoft),
        ),
      ),
    );
  }
}
