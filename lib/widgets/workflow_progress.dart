/// Per-workflow progress row for `repo_detail_screen.dart` — one row per
/// entry from `GET /api/repos/{name}/workflows` (serve-api v0.3 §11.3).
///
/// Renders `spec_slug`, task index vs. `status`, and `branch` as plain text.
/// No PR link: `WorkflowStateDto` exposes no `pr_url` field on the current
/// contract — see `planning/2.A-dashboard-repo-detail/tasks.md` Context
/// Pointers / Notes for the tracked contract gap.
library;

import 'package:flutter/material.dart';

import '../models/repo_status_dto.dart';

/// A single workflow's progress — spec slug, current task, status, branch.
class WorkflowProgress extends StatelessWidget {
  const WorkflowProgress({super.key, required this.workflow});

  /// The workflow this row renders.
  final WorkflowStateDto workflow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('workflow-progress-${workflow.specSlug}'),
      title: Text(workflow.specSlug),
      isThreeLine: true,
      subtitle: Text(
        'task ${workflow.currentTask} — ${workflow.status}\n'
        'branch: ${workflow.branch}',
      ),
    );
  }
}
