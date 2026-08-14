/// Attention DTOs mirroring `../bastion/types/serve.ts` (serve-api v0.30/v0.31
/// §15) for `GET /api/attention?scope=hq|tier|project|business[&tier=<name>]`.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// AttentionCarryoverDto
// ---------------------------------------------------------------------------

/// One `carryover[]` entry past its per-`kind` staleness threshold — backs
/// the `stale_carryover` lane. Mirrors `AttentionCarryoverDto` in
/// `types/serve.ts`, projecting `mev::CarryoverRanking` verbatim alongside
/// the original entry's display fields.
///
/// Every optional wire field serializes as an absent key when unset, never
/// `null` — this client treats "absent" and "explicit null" identically and
/// decodes both as Dart `null`.
final class AttentionCarryoverDto {
  final String repo;
  final String slug;

  /// Carryover kind (`"env"`, `"deferred"`, `"known_issue"`, `"constraint"`,
  /// or other free-form value).
  final String kind;

  /// The carryover text itself, untruncated.
  final String text;

  /// What clears this item, when recorded.
  final String? clearsWhen;

  /// Creation date (`YYYY-MM-DD`), when recorded.
  final String? created;

  /// Last-reviewed date (`YYYY-MM-DD`), when recorded.
  final String? reviewed;

  /// Days past the anchor date (`max(created, reviewed)`), as of `as_of`.
  ///
  /// **`null` when the entry is currently snoozed or has no parseable
  /// anchor date** — such entries still reach the board and must render.
  /// This was the one NON-ADDITIVE change in v0.25: `null` means "no age
  /// known", never `0`, and must never be sorted as if it were `0`.
  final int? ageDays;

  /// The per-`kind` threshold this item tripped.
  final int thresholdDays;

  /// The triage lane `mev::rank_carryover` assigned (`blocking`/`hot`/
  /// `aging`/`standing`). Never re-derived client-side.
  final String lane;

  /// Authored `priority`, verbatim from `mev::CarryoverRanking`.
  final int? priority;

  /// Effective priority (reverse-topo min-propagation over `blocks[]`
  /// edges), verbatim from `mev::CarryoverRanking`.
  final int? effectivePriority;

  /// Unmet `blocks[]` edges. Non-empty iff this entry is in the BLOCKING
  /// lane — there is deliberately no `blocking: bool` field; derive it from
  /// `unmetBlocks.isNotEmpty`.
  final List<String> unmetBlocks;

  /// Free-form cross-repo finding identity, verbatim from
  /// `mev::CarryoverRanking`.
  final String? findingId;

  /// Whether every reference extracted from `clears_when` is currently
  /// satisfied (`mev::CarryoverLane::Cleared`), verbatim from
  /// `mev::CarryoverRanking`.
  final bool clearsWhenSatisfied;

  const AttentionCarryoverDto({
    required this.repo,
    required this.slug,
    required this.kind,
    required this.text,
    this.clearsWhen,
    this.created,
    this.reviewed,
    this.ageDays,
    required this.thresholdDays,
    required this.lane,
    this.priority,
    this.effectivePriority,
    this.unmetBlocks = const [],
    this.findingId,
    required this.clearsWhenSatisfied,
  });

  factory AttentionCarryoverDto.fromJson(Map<String, dynamic> json) {
    final rawUnmetBlocks = json['unmet_blocks'];
    return AttentionCarryoverDto(
      repo: json['repo'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      text: json['text'] as String? ?? '',
      clearsWhen: json['clears_when'] as String?,
      created: json['created'] as String?,
      reviewed: json['reviewed'] as String?,
      ageDays: (json['age_days'] as num?)?.toInt(),
      thresholdDays: (json['threshold_days'] as num?)?.toInt() ?? 0,
      lane: json['lane'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt(),
      effectivePriority: (json['effective_priority'] as num?)?.toInt(),
      unmetBlocks: rawUnmetBlocks is List
          ? rawUnmetBlocks.whereType<String>().toList()
          : const [],
      findingId: json['finding_id'] as String?,
      clearsWhenSatisfied: json['clears_when_satisfied'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// AttentionBacklogDto
// ---------------------------------------------------------------------------

/// One `backlog[]` node that has crossed the backlog staleness threshold —
/// backs BOTH the `aging_backlog` lane (non-capture nodes) and the
/// `orphaned_captures` lane (`origin.type == "capture"` nodes, never both).
/// One type, two lanes. Mirrors `AttentionBacklogDto` in `types/serve.ts`.
final class AttentionBacklogDto {
  final String repo;
  final String slug;
  final String title;

  /// Backlog kind (serde-renamed from `type` on the domain type).
  final String kind;

  /// Lifecycle status (`"idea"` / `"ready"`, the only statuses that can
  /// age).
  final String status;

  /// Notes; for `orphaned_captures` this is `origin.notes` falling back to
  /// the node's own `notes`.
  final String? notes;

  /// Creation date (`YYYY-MM-DD`), when recorded.
  final String? created;

  /// Last-reviewed date (`YYYY-MM-DD`), when recorded.
  final String? reviewed;

  /// Days past the anchor date (`max(created, reviewed)`), as of `as_of`.
  final int ageDays;

  /// The `backlog_days` threshold this item tripped.
  final int thresholdDays;

  const AttentionBacklogDto({
    required this.repo,
    required this.slug,
    required this.title,
    required this.kind,
    required this.status,
    this.notes,
    this.created,
    this.reviewed,
    required this.ageDays,
    required this.thresholdDays,
  });

  factory AttentionBacklogDto.fromJson(Map<String, dynamic> json) {
    return AttentionBacklogDto(
      repo: json['repo'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
      notes: json['notes'] as String?,
      created: json['created'] as String?,
      reviewed: json['reviewed'] as String?,
      ageDays: (json['age_days'] as num?)?.toInt() ?? 0,
      thresholdDays: (json['threshold_days'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// AttentionLanesDto
// ---------------------------------------------------------------------------

/// The three Attention board lanes — mirrors `AttentionLanesDto` in
/// `types/serve.ts`. All three keys are OPTIONAL on the wire; an absent lane
/// defaults to an empty list.
final class AttentionLanesDto {
  /// `carryover[]` entries past their per-`kind` threshold, oldest-first.
  final List<AttentionCarryoverDto> staleCarryover;

  /// Non-capture `backlog[]` nodes past `backlog_days`, oldest-first.
  final List<AttentionBacklogDto> agingBacklog;

  /// `backlog[]` nodes with `origin.type == "capture"` past
  /// `backlog_days`, oldest-first.
  final List<AttentionBacklogDto> orphanedCaptures;

  const AttentionLanesDto({
    this.staleCarryover = const [],
    this.agingBacklog = const [],
    this.orphanedCaptures = const [],
  });

  static List<AttentionCarryoverDto> _carryoverList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AttentionCarryoverDto.fromJson)
        .toList();
  }

  static List<AttentionBacklogDto> _backlogList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AttentionBacklogDto.fromJson)
        .toList();
  }

  factory AttentionLanesDto.fromJson(Map<String, dynamic> json) {
    return AttentionLanesDto(
      staleCarryover: _carryoverList(json['stale_carryover']),
      agingBacklog: _backlogList(json['aging_backlog']),
      orphanedCaptures: _backlogList(json['orphaned_captures']),
    );
  }
}

// ---------------------------------------------------------------------------
// AttentionThresholdsDto
// ---------------------------------------------------------------------------

/// The resolved `brain.toml` `[attention]` thresholds, mirroring
/// `AttentionThresholdsDto` in `types/serve.ts`
/// (`mev::brain::config::AttentionThresholds`).
final class AttentionThresholdsDto {
  /// Threshold (days) for `kind == "env"` carryover.
  final int envDays;

  /// Threshold (days) for `kind == "deferred"` carryover.
  final int deferredDays;

  /// Threshold (days) for `kind == "known_issue"` carryover.
  final int knownIssueDays;

  /// Threshold (days) for `kind == "constraint"` carryover.
  final int constraintDays;

  /// Threshold (days) for aging/orphaned `backlog[]` nodes.
  final int backlogDays;

  const AttentionThresholdsDto({
    required this.envDays,
    required this.deferredDays,
    required this.knownIssueDays,
    required this.constraintDays,
    required this.backlogDays,
  });

  factory AttentionThresholdsDto.fromJson(Map<String, dynamic> json) {
    return AttentionThresholdsDto(
      envDays: (json['env_days'] as num?)?.toInt() ?? 0,
      deferredDays: (json['deferred_days'] as num?)?.toInt() ?? 0,
      knownIssueDays: (json['known_issue_days'] as num?)?.toInt() ?? 0,
      constraintDays: (json['constraint_days'] as num?)?.toInt() ?? 0,
      backlogDays: (json['backlog_days'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// AttentionDto — GET /api/attention response
// ---------------------------------------------------------------------------

/// JSON response for `GET /api/attention?scope=hq|tier|project|business
/// [&tier=<name>]` — mirrors `AttentionDto` in `types/serve.ts`.
final class AttentionDto {
  /// The resolved scope this response was projected under. Reuses the same
  /// scope vocabulary as `/api/board` (`"hq"`/`"tier"`/`"project"`/
  /// `"business"`/`"epic"`).
  final String? scope;

  /// The resolved tier name, when `scope` is tier-scoped (absent for
  /// `hq`).
  final String? tier;

  /// `YYYY-MM-DD` the ages were computed against.
  final String asOf;

  /// The three Attention lanes.
  final AttentionLanesDto lanes;

  /// The resolved thresholds used to compute every `age_days` /
  /// `threshold_days` pair above.
  final AttentionThresholdsDto thresholds;

  const AttentionDto({
    this.scope,
    this.tier,
    required this.asOf,
    this.lanes = const AttentionLanesDto(),
    required this.thresholds,
  });

  factory AttentionDto.fromJson(Map<String, dynamic> json) {
    final rawLanes = json['lanes'];
    final rawThresholds = json['thresholds'];
    return AttentionDto(
      scope: json['scope'] as String?,
      tier: json['tier'] as String?,
      asOf: json['as_of'] as String? ?? '',
      lanes: rawLanes is Map<String, dynamic>
          ? AttentionLanesDto.fromJson(rawLanes)
          : const AttentionLanesDto(),
      thresholds: rawThresholds is Map<String, dynamic>
          ? AttentionThresholdsDto.fromJson(rawThresholds)
          : const AttentionThresholdsDto(
              envDays: 0,
              deferredDays: 0,
              knownIssueDays: 0,
              constraintDays: 0,
              backlogDays: 0,
            ),
    );
  }
}
