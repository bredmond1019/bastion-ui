/// Fleet-scoped lane DTOs mirroring `../bastion/docs/serve-api.md` §28
/// (v0.35, `BA.19.C`) for `GET /api/lanes` (optionally `&epic=<slug>`).
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// LaneSegmentDto
// ---------------------------------------------------------------------------

/// One row of mev's corpus-wide lane-segment availability — mirrors
/// `LaneSegmentDto` in `types/serve.ts`.
final class LaneSegmentDto {
  final String roadmap;
  final String lane;
  final int segment;
  final String repo;

  /// Canonical `"repo:id"` key of the segment's head block. Absent (not an
  /// empty string) for a `done` segment — every block in it is closed, so
  /// there is no frontier entry and therefore no head.
  final String? head;

  /// mev's `SegmentAvailability` variant, kebab-case, carried verbatim
  /// (`"done"`, `"held-block"`, `"held-operator"`, `"held-repo-busy"`,
  /// `"held-slot"`, or `"startable"`). Deliberately a plain string, not an
  /// enum: mev owns this vocabulary and a mirrored enum would silently stop
  /// covering a state the moment mev adds a new one.
  final String availability;

  /// Human-readable why. Absent (not a blank string) only for `startable`
  /// and `done`, which need no explanation.
  final String? reason;

  /// Count of distinct `(roadmap, lane)` pairs freed by closing this
  /// segment. On a `done` segment this value is historical, not
  /// actionable — a consumer must not treat it as something still to
  /// unblock.
  final int leverageLanesFreed;

  const LaneSegmentDto({
    required this.roadmap,
    required this.lane,
    required this.segment,
    required this.repo,
    this.head,
    required this.availability,
    this.reason,
    required this.leverageLanesFreed,
  });

  factory LaneSegmentDto.fromJson(Map<String, dynamic> json) {
    return LaneSegmentDto(
      roadmap: json['roadmap'] as String? ?? '',
      lane: json['lane'] as String? ?? '',
      segment: (json['segment'] as num?)?.toInt() ?? 0,
      repo: json['repo'] as String? ?? '',
      head: json['head'] as String?,
      availability: json['availability'] as String? ?? '',
      reason: json['reason'] as String?,
      leverageLanesFreed: (json['leverage_lanes_freed'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// LanesDto — GET /api/lanes response
// ---------------------------------------------------------------------------

/// JSON response for `GET /api/lanes` (optionally `&epic=<slug>`) — mirrors
/// `LanesDto` in `types/serve.ts`.
final class LanesDto {
  /// RFC 3339 timestamp of the derivation run.
  final String derivedAt;

  /// `true` when the fleet-lock read that feeds the `held-slot` availability
  /// state degraded — lets a consumer tell a corpus with zero live holds
  /// apart from one where the fleet-lock read itself failed.
  final bool degraded;

  /// One row per lane segment fleet-wide (or, with `?epic=<slug>`, per
  /// segment whose `roadmap` matches). A known-but-unmatched slug legitimately
  /// returns an empty list — a real answer, not an error.
  final List<LaneSegmentDto> segments;

  const LanesDto({
    required this.derivedAt,
    this.degraded = false,
    this.segments = const [],
  });

  factory LanesDto.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];
    return LanesDto(
      derivedAt: json['derived_at'] as String? ?? '',
      degraded: json['degraded'] as bool? ?? false,
      segments: rawSegments is List
          ? rawSegments
                .whereType<Map<String, dynamic>>()
                .map(LaneSegmentDto.fromJson)
                .toList()
          : const [],
    );
  }
}
