/// Board DTOs mirroring `../bastion/types/serve.ts` (serve-api v0.30/v0.31
/// §13) for `GET /api/board?scope=hq|tier|project|business` (optionally
/// `&tier=<name>&graph=1`).
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// BlockedBy — mirrors okf_core::BlockedBy (internally tagged on "type")
// ---------------------------------------------------------------------------

/// One entry of `BoardBlockDto.blockedBy` — mirrors `okf_core::BlockedBy`,
/// an internally-tagged Rust enum (`#[serde(tag = "type")]`) with four
/// variants: `block`, `external`, `operator`, `approval`.
///
/// **Defensive decoding**: `okf_core::BlockedBy`'s typeshare export is a
/// known open item upstream (`OK.ticket.blockedby-typeshare-export` — "export
/// `okf_core::BlockedBy` through typeshare so all four variants reach the
/// wire") and is therefore ABSENT from `../bastion/types/serve.ts` entirely.
/// This client cannot assume all four variants are present on the wire
/// today, or that a future upstream fix keeps today's shape. Each entry is
/// decoded into a typed subtype when its `type`/fields are recognised; any
/// other shape (an unknown `type`, or a recognised `type` missing required
/// fields) degrades to [UnknownBlockedBy], carrying the raw map, rather than
/// throwing — the same degrade-not-throw posture [BastionFrame] uses for an
/// unknown WS frame `kind`.
sealed class BlockedByDto {
  const BlockedByDto();

  factory BlockedByDto.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) {
      return UnknownBlockedByDto(raw: json);
    }
    switch (type) {
      case 'block':
        final repo = json['repo'];
        final id = json['id'];
        if (repo is String && id is String) {
          return BlockDepDto(repo: repo, id: id, what: json['what'] as String?);
        }
        return UnknownBlockedByDto(raw: json);
      case 'external':
        final what = json['what'];
        if (what is String) {
          return ExternalDepDto(what: what);
        }
        return UnknownBlockedByDto(raw: json);
      case 'operator':
        final slug = json['slug'];
        final exit = json['exit'];
        final start = json['start'];
        if (slug is String && exit is String && start is String) {
          return OperatorDepDto(
            slug: slug,
            exit: exit,
            start: start,
            what: json['what'] as String?,
          );
        }
        return UnknownBlockedByDto(raw: json);
      case 'approval':
        final slug = json['slug'];
        final what = json['what'];
        final digest = json['digest'];
        if (slug is String && what is String && digest is String) {
          return ApprovalDepDto(slug: slug, what: what, digest: digest);
        }
        return UnknownBlockedByDto(raw: json);
      default:
        return UnknownBlockedByDto(raw: json);
    }
  }
}

/// A dependency on another block (may be cross-repo) — `BlockedBy::Block`.
final class BlockDepDto extends BlockedByDto {
  final String repo;
  final String id;
  final String? what;

  const BlockDepDto({required this.repo, required this.id, this.what});
}

/// An environmental / external dependency — `BlockedBy::External`.
final class ExternalDepDto extends BlockedByDto {
  final String what;

  const ExternalDepDto({required this.what});
}

/// An operator working session that gates this block — `BlockedBy::Operator`.
final class OperatorDepDto extends BlockedByDto {
  final String slug;
  final String exit;
  final String start;
  final String? what;

  const OperatorDepDto({
    required this.slug,
    required this.exit,
    required this.start,
    this.what,
  });
}

/// A gated action awaiting a single operator decision — `BlockedBy::Approval`.
final class ApprovalDepDto extends BlockedByDto {
  final String slug;
  final String what;
  final String digest;

  const ApprovalDepDto({
    required this.slug,
    required this.what,
    required this.digest,
  });
}

/// An unrecognised `blocked_by` entry — an unknown `type`, or a recognised
/// `type` missing required fields. Carries the raw decoded map so nothing is
/// lost; a future upstream typeshare fix must not break this client.
final class UnknownBlockedByDto extends BlockedByDto {
  final Map<String, dynamic> raw;

  const UnknownBlockedByDto({required this.raw});
}

// ---------------------------------------------------------------------------
// BoardBlockDto
// ---------------------------------------------------------------------------

/// One lane entry (a single now/next/blocked/deferred/finished block) in a
/// board response — mirrors `BoardBlockDto` in `types/serve.ts`.
///
/// ```json
/// {"id": "BA.11.K", "title": "Cross-brain board read endpoint",
///  "repo": "bastion", "status": "in_progress", "blocked_by": [],
///  "epics": ["bastion-surfaces"], "wave": 3}
/// ```
final class BoardBlockDto {
  final String id;
  final String title;
  final String repo;
  final String? status;
  final List<BlockedByDto> blockedBy;
  final List<String> epics;
  final int? wave;

  /// Corpus-wide count of blocks whose `blocked_by` edges point at this
  /// block. **`null` unless the request passed `?graph=1`** — the field is
  /// omitted from the wire entirely otherwise (v0.19 opt-in graph
  /// enrichment). `null` means "not requested", never a fabricated zero:
  /// mev's own `dependent_count` is `0` for a block nothing depends on, so
  /// `0` and `null` are deliberately distinct here.
  final int? dependentCount;

  /// Membership in mev's ready-order set. **`null` unless `?graph=1`** was
  /// passed — same opt-in-only posture as [dependentCount]. This is the
  /// readiness signal to use; never derive readiness from
  /// `unmetCount == 0`.
  final bool? ready;

  /// Count of unmet dependencies, populated only for `blocked`-lane entries
  /// even when `?graph=1` is requested; `null` for every other lane, and
  /// also `null` when `?graph=1` was not requested at all. Never treat
  /// `null` as `0`.
  final int? unmetCount;

  /// Timestamp of the block's most recent recorded activity — serve-api
  /// **v0.14** (`BA.11.S`), also `last_touched?: string` in
  /// `bastion/types/serve.ts:389`.
  ///
  /// **`null` here means "never worked", NOT "worked long ago".** The wire
  /// field is omitted from the JSON body entirely when unknown
  /// (`skip_serializing_if`) — a deliberate divergence from the
  /// [dependentCount]/[ready]/[unmetCount] siblings' `?graph=1`-gated `null`
  /// convention above: this field's absence is unconditional and always
  /// carries that one meaning, on every request regardless of `?graph=1`.
  /// Never substitute a sentinel date, an epoch, or `state.json.updated`
  /// for a missing value — the contract forbids all three. Callers deriving
  /// a repo's recency (the newest [lastTouched] across its blocks) MUST
  /// treat "every block's [lastTouched] is `null`" as its own state
  /// ("never worked"), distinct from any known, however old, timestamp —
  /// collapsing the two is the same class of bug as rendering `null` as
  /// `0` (`BU.ticket.dashboard-now-render`).
  final DateTime? lastTouched;

  const BoardBlockDto({
    required this.id,
    required this.title,
    required this.repo,
    this.status,
    this.blockedBy = const [],
    this.epics = const [],
    this.wave,
    this.dependentCount,
    this.ready,
    this.unmetCount,
    this.lastTouched,
  });

  factory BoardBlockDto.fromJson(Map<String, dynamic> json) {
    final rawBlockedBy = json['blocked_by'];
    final rawEpics = json['epics'];
    final rawLastTouched = json['last_touched'];
    return BoardBlockDto(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      status: json['status'] as String?,
      blockedBy: rawBlockedBy is List
          ? rawBlockedBy
                .whereType<Map<String, dynamic>>()
                .map(BlockedByDto.fromJson)
                .toList()
          : const [],
      epics: rawEpics is List
          ? rawEpics.whereType<String>().toList()
          : const [],
      wave: (json['wave'] as num?)?.toInt(),
      dependentCount: (json['dependent_count'] as num?)?.toInt(),
      ready: json['ready'] as bool?,
      unmetCount: (json['unmet_count'] as num?)?.toInt(),
      lastTouched: rawLastTouched is String
          ? DateTime.tryParse(rawLastTouched)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// BoardLaneDto
// ---------------------------------------------------------------------------

/// The five now/next/blocked/deferred/finished lanes for one board
/// (aggregate or per-repo) — mirrors `BoardLaneDto` in `types/serve.ts`.
/// Every lane key is optional on the wire; an absent lane defaults to an
/// empty list.
final class BoardLaneDto {
  final List<BoardBlockDto> now;
  final List<BoardBlockDto> next;
  final List<BoardBlockDto> blocked;
  final List<BoardBlockDto> deferred;
  final List<BoardBlockDto> finished;

  const BoardLaneDto({
    this.now = const [],
    this.next = const [],
    this.blocked = const [],
    this.deferred = const [],
    this.finished = const [],
  });

  static List<BoardBlockDto> _list(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(BoardBlockDto.fromJson)
        .toList();
  }

  factory BoardLaneDto.fromJson(Map<String, dynamic> json) {
    return BoardLaneDto(
      now: _list(json['now']),
      next: _list(json['next']),
      blocked: _list(json['blocked']),
      deferred: _list(json['deferred']),
      finished: _list(json['finished']),
    );
  }
}

// ---------------------------------------------------------------------------
// RepoBoardDto
// ---------------------------------------------------------------------------

/// One repo's lane breakdown within a `scope=project` board response.
final class RepoBoardDto {
  final String repo;
  final String? tier;
  final BoardLaneDto lanes;

  const RepoBoardDto({
    required this.repo,
    this.tier,
    this.lanes = const BoardLaneDto(),
  });

  factory RepoBoardDto.fromJson(Map<String, dynamic> json) {
    final rawLanes = json['lanes'];
    return RepoBoardDto(
      repo: json['repo'] as String? ?? '',
      tier: json['tier'] as String?,
      lanes: rawLanes is Map<String, dynamic>
          ? BoardLaneDto.fromJson(rawLanes)
          : const BoardLaneDto(),
    );
  }
}

// ---------------------------------------------------------------------------
// BoardDto — GET /api/board response
// ---------------------------------------------------------------------------

/// JSON response for `GET /api/board?scope=hq|tier|project|business`
/// (optionally `&tier=<name>&graph=1`) — mirrors `BoardDto` in
/// `types/serve.ts`.
final class BoardDto {
  /// Resolved scope string (`"hq"`/`"tier"`/`"project"`/`"business"`/
  /// `"epic"`), when present.
  final String? scope;

  /// Resolved tier name, when `scope` is tier-scoped (absent for `hq`).
  final String? tier;

  /// Aggregate lanes across all in-scope repos.
  final BoardLaneDto lanes;

  /// Per-project lane breakdown (populated for `scope=project`; empty
  /// otherwise).
  final List<RepoBoardDto> repos;

  /// Freshness flag: `true` when any in-scope repo's `status.md` cache lags
  /// its `state.json`.
  final bool stale;

  const BoardDto({
    this.scope,
    this.tier,
    this.lanes = const BoardLaneDto(),
    this.repos = const [],
    this.stale = false,
  });

  factory BoardDto.fromJson(Map<String, dynamic> json) {
    final rawLanes = json['lanes'];
    final rawRepos = json['repos'];
    return BoardDto(
      scope: json['scope'] as String?,
      tier: json['tier'] as String?,
      lanes: rawLanes is Map<String, dynamic>
          ? BoardLaneDto.fromJson(rawLanes)
          : const BoardLaneDto(),
      repos: rawRepos is List
          ? rawRepos
                .whereType<Map<String, dynamic>>()
                .map(RepoBoardDto.fromJson)
                .toList()
          : const [],
      stale: json['stale'] as bool? ?? false,
    );
  }
}
