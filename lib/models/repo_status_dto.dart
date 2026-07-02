/// Repo + workflow status DTOs mirroring serve-api.md (v0.3) §11.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// GET /api/repos → RepoSummaryDto[]
// ---------------------------------------------------------------------------

/// One row of the dashboard's repo list (serve-api §11).
///
/// ```json
/// {"name": "bastion-ui", "now": "wiring dashboard", "has_handoff": true}
/// ```
final class RepoSummaryDto {
  final String name;
  final String now;
  final bool hasHandoff;

  const RepoSummaryDto({
    required this.name,
    required this.now,
    required this.hasHandoff,
  });

  factory RepoSummaryDto.fromJson(Map<String, dynamic> json) {
    return RepoSummaryDto(
      name: json['name'] as String? ?? '',
      now: json['now'] as String? ?? '',
      hasHandoff: json['has_handoff'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'now': now,
    'has_handoff': hasHandoff,
  };
}

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/status → RepoStatusDto
// ---------------------------------------------------------------------------

/// The parsed `status.md` for a single repo (serve-api §11).
///
/// ```json
/// {
///   "name": "bastion-ui",
///   "now": "wiring dashboard",
///   "next": "repo detail",
///   "blocked": "",
///   "has_handoff": true,
///   "momentum_now": "...",
///   "momentum_next": "...",
///   "momentum_blocked": "...",
///   "momentum_improve": "...",
///   "momentum_recurring": "..."
/// }
/// ```
final class RepoStatusDto {
  final String name;
  final String now;
  final String next;
  final String blocked;
  final bool hasHandoff;
  final String momentumNow;
  final String momentumNext;
  final String momentumBlocked;
  final String momentumImprove;
  final String momentumRecurring;

  const RepoStatusDto({
    required this.name,
    required this.now,
    required this.next,
    required this.blocked,
    required this.hasHandoff,
    required this.momentumNow,
    required this.momentumNext,
    required this.momentumBlocked,
    required this.momentumImprove,
    required this.momentumRecurring,
  });

  factory RepoStatusDto.fromJson(Map<String, dynamic> json) {
    return RepoStatusDto(
      name: json['name'] as String? ?? '',
      now: json['now'] as String? ?? '',
      next: json['next'] as String? ?? '',
      blocked: json['blocked'] as String? ?? '',
      hasHandoff: json['has_handoff'] as bool? ?? false,
      momentumNow: json['momentum_now'] as String? ?? '',
      momentumNext: json['momentum_next'] as String? ?? '',
      momentumBlocked: json['momentum_blocked'] as String? ?? '',
      momentumImprove: json['momentum_improve'] as String? ?? '',
      momentumRecurring: json['momentum_recurring'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'now': now,
    'next': next,
    'blocked': blocked,
    'has_handoff': hasHandoff,
    'momentum_now': momentumNow,
    'momentum_next': momentumNext,
    'momentum_blocked': momentumBlocked,
    'momentum_improve': momentumImprove,
    'momentum_recurring': momentumRecurring,
  };
}

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/handoff → HandoffInfo
// ---------------------------------------------------------------------------

/// The parsed `handoff.md` for a single repo (serve-api §11).
///
/// Absent (404 / `C002`) when the repo has no `handoff.md` — callers should
/// surface that as a typed null, not throw.
///
/// ```json
/// {"title": "Handoff — BU.1.A", "body": "## Summary\n..."}
/// ```
final class HandoffInfo {
  final String title;
  final String body;

  const HandoffInfo({required this.title, required this.body});

  factory HandoffInfo.fromJson(Map<String, dynamic> json) {
    return HandoffInfo(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
}

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/workflows → WorkflowStateDto[]
// ---------------------------------------------------------------------------

/// A single in-flight or completed SDLC workflow for a repo (serve-api §11).
///
/// ```json
/// {
///   "spec_slug": "2.A-dashboard-repo-detail",
///   "branch": "2.A-dashboard-repo-detail-flow",
///   "status": "running",
///   "current_task": 5,
///   "started_at": "2026-07-02T10:00:00Z",
///   "updated_at": "2026-07-02T10:15:00Z"
/// }
/// ```
///
/// Per serve-api.md §11.3, `current_task` is an **integer** task index (not
/// a string, despite the spec's summary table) — mirrored as `int` here.
///
/// No PR-link field exists on this DTO (contract gap — see spec Notes);
/// `branch` is rendered as plain text by the UI, never a link.
final class WorkflowStateDto {
  final String specSlug;
  final String branch;
  final String status;
  final int currentTask;
  final String startedAt;
  final String updatedAt;

  const WorkflowStateDto({
    required this.specSlug,
    required this.branch,
    required this.status,
    required this.currentTask,
    required this.startedAt,
    required this.updatedAt,
  });

  factory WorkflowStateDto.fromJson(Map<String, dynamic> json) {
    return WorkflowStateDto(
      specSlug: json['spec_slug'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      status: json['status'] as String? ?? '',
      currentTask: (json['current_task'] as num?)?.toInt() ?? 0,
      startedAt: json['started_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'spec_slug': specSlug,
    'branch': branch,
    'status': status,
    'current_task': currentTask,
    'started_at': startedAt,
    'updated_at': updatedAt,
  };
}
