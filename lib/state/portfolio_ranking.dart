/// Pure, Flutter-free tiering logic for the Dashboard/Portfolio screen
/// (`BU.13.D` task 2).
///
/// This file has ZERO Flutter imports — it operates only on the
/// already-decoded wire DTOs (`RepoBoardDto` / `BoardLaneDto` /
/// `BoardBlockDto`) and an explicitly injected `now`. `dashboard_screen.dart`
/// (task 3) renders the result; nothing in here reads the wall clock, or the
/// tiering tests (`test/state/portfolio_ranking_test.dart`) could not be
/// deterministic.
///
/// ## `neverWorked` is not a very old date
///
/// `BoardBlockDto.lastTouched` is `null` when a block has never had recorded
/// activity (see that field's doc comment — the wire omits the key
/// entirely). A repo's recency is the newest `lastTouched` across its
/// blocks; when NO block has one, the repo is [RepoRecencyNeverWorked] — a
/// distinct state, not [RepoRecencyKnown] holding a fabricated old
/// timestamp. [rankPortfolio] never lets a `neverWorked` repo tier as
/// stale: the drift-promotion rule below only ever fires for a
/// [RepoRecencyKnown] recency, so a brand-new repo without any blocked
/// blocks or open gates lands in [PortfolioTier.quiet], not
/// [PortfolioTier.needsAttention] — conflating "never worked" with "worked
/// long ago" is the same class of bug as rendering `null` as `0`
/// (`BU.ticket.dashboard-now-render`).
///
/// ## Tiering rules
///
/// - [PortfolioTier.needsAttention]: the repo has at least one blocked
///   block, OR at least one block whose `blocked_by` names an operator/
///   approval gate ("an open gate"), OR — the drift-promotion rule — the
///   repo has nothing in flight (`now` lane empty) AND its known recency is
///   at or past [kDefaultPortfolioStaleThreshold] (or a caller-supplied
///   threshold). Drift with nothing in flight is the exact signal this
///   screen exists to surface (spec Goal).
/// - [PortfolioTier.active]: not needs-attention, and the repo has at least
///   one block in its `now` lane.
/// - [PortfolioTier.quiet]: everything else — including every
///   `neverWorked` repo that has no blocked blocks or open gates, and a
///   repo with zero blocks at all.
///
/// ## Ordering
///
/// Within [PortfolioTier.needsAttention], most-blocked-blocks first, then
/// open-gate presence, then oldest known recency first (drift-only entries
/// sort by how stale they are), then repo name ascending as the final,
/// always-available tie-break. Within [PortfolioTier.active], most
/// in-flight blocks first, then repo name ascending. Within
/// [PortfolioTier.quiet], most-recently-touched first, `neverWorked` repos
/// last (they have no recency to rank by), then repo name ascending within
/// each group. Every comparator bottoms out on repo name so order is
/// stable across rebuilds regardless of input ordering.
library;

import '../models/board_dto.dart';

/// The default repo-level staleness threshold used by the drift-promotion
/// rule: a repo with nothing in flight, last touched a week or more ago, is
/// drifting and belongs in [PortfolioTier.needsAttention].
///
/// Deliberately coarser than [kDefaultAgeChipStaleThreshold]
/// (`lib/widgets/instrument/age_chip.dart`, one day) — that chip flags a
/// single block's staleness at a finer grain; this threshold governs
/// whether a whole repo with nothing currently in flight has gone quiet
/// long enough to need the operator's attention.
const Duration kDefaultPortfolioStaleThreshold = Duration(days: 7);

// ---------------------------------------------------------------------------
// RepoRecency — "never worked" as a distinct state, not a nullable DateTime
// ---------------------------------------------------------------------------

/// A repo's derived recency: either a [RepoRecencyKnown] timestamp (the
/// newest `lastTouched` across its blocks) or [RepoRecencyNeverWorked] when
/// no block carries one. Modelled as a sealed class rather than a nullable
/// `DateTime` precisely so callers cannot forget to check — there is no
/// `DateTime?` to accidentally treat as "very old" or feed straight into
/// `AgeChip.since`.
sealed class RepoRecency {
  const RepoRecency();

  /// Derives a repo's recency as the newest non-null `lastTouched` across
  /// [touched]. Returns [RepoRecencyNeverWorked] when every value is
  /// `null` (including when [touched] is empty — a repo with zero blocks).
  factory RepoRecency.newestOf(Iterable<DateTime?> touched) {
    DateTime? newest;
    for (final t in touched) {
      if (t == null) continue;
      if (newest == null || t.isAfter(newest)) newest = t;
    }
    return newest == null
        ? const RepoRecencyNeverWorked()
        : RepoRecencyKnown(newest);
  }
}

/// The repo has at least one block with a known `lastTouched`; [lastTouched]
/// is the newest one.
final class RepoRecencyKnown extends RepoRecency {
  final DateTime lastTouched;

  const RepoRecencyKnown(this.lastTouched);
}

/// No block in the repo has ever recorded a `lastTouched` — the repo has
/// never been worked. Distinct from any known, however old, timestamp.
final class RepoRecencyNeverWorked extends RepoRecency {
  const RepoRecencyNeverWorked();
}

// ---------------------------------------------------------------------------
// PortfolioTier
// ---------------------------------------------------------------------------

/// The three groups the Dashboard ranks repos into. Order in the enum is
/// the screen's display order (needs-attention first).
enum PortfolioTier { needsAttention, active, quiet }

// ---------------------------------------------------------------------------
// PortfolioRepoEntry
// ---------------------------------------------------------------------------

/// One repo, tiered, with the derived figures the screen (and task 3's
/// `LaneBar`) need to render it.
final class PortfolioRepoEntry {
  /// The source DTO this entry was derived from.
  final RepoBoardDto repo;

  /// The tier this repo landed in.
  final PortfolioTier tier;

  /// The repo's derived recency — see [RepoRecency].
  final RepoRecency recency;

  /// Count of blocks in the `finished` lane — the `LaneBar`'s `done`
  /// segment (task 3).
  final int doneCount;

  /// Count of blocks in the `now` lane.
  final int nowCount;

  /// Count of blocks in the `blocked` lane.
  final int blockedCount;

  /// Count of blocks in the `next` lane.
  final int nextCount;

  /// Count of blocks in the `deferred` lane — not one of `LaneBar`'s four
  /// segments, but still part of the repo's total block count.
  final int deferredCount;

  /// Whether any block in this repo has a `blocked_by` entry naming an
  /// operator or approval gate.
  final bool hasOpenGate;

  const PortfolioRepoEntry({
    required this.repo,
    required this.tier,
    required this.recency,
    required this.doneCount,
    required this.nowCount,
    required this.blockedCount,
    required this.nextCount,
    required this.deferredCount,
    required this.hasOpenGate,
  });

  /// Repo name, forwarded for convenience.
  String get name => repo.repo;

  /// Total block count across every lane, including `deferred` — this is
  /// the figure task 3's `LaneBar` assertion (its four segments sum to the
  /// repo's block total) must reconcile against, so callers that need to
  /// assert the bar-only total should sum [doneCount] + [nowCount] +
  /// [blockedCount] + [nextCount] directly rather than use this getter.
  int get blockTotal =>
      doneCount + nowCount + blockedCount + nextCount + deferredCount;
}

// ---------------------------------------------------------------------------
// PortfolioRanking — the three tiered, ordered lists
// ---------------------------------------------------------------------------

/// The result of [rankPortfolio]: every input repo, tiered and ordered.
final class PortfolioRanking {
  final List<PortfolioRepoEntry> needsAttention;
  final List<PortfolioRepoEntry> active;
  final List<PortfolioRepoEntry> quiet;

  const PortfolioRanking({
    required this.needsAttention,
    required this.active,
    required this.quiet,
  });

  /// All entries across all three tiers, in tier-then-within-tier order.
  List<PortfolioRepoEntry> get all => [...needsAttention, ...active, ...quiet];
}

// ---------------------------------------------------------------------------
// rankPortfolio — the pure tiering function
// ---------------------------------------------------------------------------

/// Whether [block]'s `blocked_by` names an operator- or approval-type gate
/// — the same "an operator action stands in the way" test
/// `briefing_model.dart`'s `rankOperatorGates` applies per-block, reused
/// here per-repo.
bool _isOpenGate(BoardBlockDto block) {
  return block.blockedBy.any((d) => d is OperatorDepDto || d is ApprovalDepDto);
}

/// Tiers and orders [repos] into a [PortfolioRanking]. Pure: never reads
/// the wall clock — [now] must be supplied by the caller, and
/// [staleThreshold] governs the drift-promotion rule (see the module doc).
PortfolioRanking rankPortfolio(
  List<RepoBoardDto> repos, {
  required DateTime now,
  Duration staleThreshold = kDefaultPortfolioStaleThreshold,
}) {
  final entries = repos.map((repo) {
    final lanes = repo.lanes;
    final allBlocks = [
      ...lanes.now,
      ...lanes.next,
      ...lanes.blocked,
      ...lanes.deferred,
      ...lanes.finished,
    ];
    final recency = RepoRecency.newestOf(allBlocks.map((b) => b.lastTouched));
    final hasOpenGate = lanes.blocked.any(_isOpenGate);
    final hasBlocked = lanes.blocked.isNotEmpty;
    final hasInFlight = lanes.now.isNotEmpty;

    final isDrifting =
        !hasInFlight &&
        recency is RepoRecencyKnown &&
        now.difference(recency.lastTouched) >= staleThreshold;

    final PortfolioTier tier;
    if (hasBlocked || hasOpenGate || isDrifting) {
      tier = PortfolioTier.needsAttention;
    } else if (hasInFlight) {
      tier = PortfolioTier.active;
    } else {
      tier = PortfolioTier.quiet;
    }

    return PortfolioRepoEntry(
      repo: repo,
      tier: tier,
      recency: recency,
      doneCount: lanes.finished.length,
      nowCount: lanes.now.length,
      blockedCount: lanes.blocked.length,
      nextCount: lanes.next.length,
      deferredCount: lanes.deferred.length,
      hasOpenGate: hasOpenGate,
    );
  }).toList();

  final needsAttention =
      entries.where((e) => e.tier == PortfolioTier.needsAttention).toList()
        ..sort(_compareNeedsAttention);
  final active = entries.where((e) => e.tier == PortfolioTier.active).toList()
    ..sort(_compareActive);
  final quiet = entries.where((e) => e.tier == PortfolioTier.quiet).toList()
    ..sort(_compareQuiet);

  return PortfolioRanking(
    needsAttention: needsAttention,
    active: active,
    quiet: quiet,
  );
}

/// Most-blocked first, then open-gate presence, then oldest known recency
/// first (a `neverWorked` entry here only arrived via blocked/gate, so it
/// sorts after every known recency), then repo name ascending.
int _compareNeedsAttention(PortfolioRepoEntry a, PortfolioRepoEntry b) {
  final blockedCmp = b.blockedCount.compareTo(a.blockedCount);
  if (blockedCmp != 0) return blockedCmp;

  final gateCmp = (b.hasOpenGate ? 1 : 0).compareTo(a.hasOpenGate ? 1 : 0);
  if (gateCmp != 0) return gateCmp;

  final aKnown = a.recency is RepoRecencyKnown;
  final bKnown = b.recency is RepoRecencyKnown;
  if (aKnown && bKnown) {
    final aTime = (a.recency as RepoRecencyKnown).lastTouched;
    final bTime = (b.recency as RepoRecencyKnown).lastTouched;
    final ageCmp = aTime.compareTo(bTime); // older (smaller) first
    if (ageCmp != 0) return ageCmp;
  } else if (aKnown != bKnown) {
    // Known recency (however old) is more actionable than "never worked";
    // sort it first.
    return aKnown ? -1 : 1;
  }

  return a.name.compareTo(b.name);
}

/// Most in-flight blocks first, then repo name ascending.
int _compareActive(PortfolioRepoEntry a, PortfolioRepoEntry b) {
  final nowCmp = b.nowCount.compareTo(a.nowCount);
  if (nowCmp != 0) return nowCmp;
  return a.name.compareTo(b.name);
}

/// Most-recently-touched first; `neverWorked` entries sort after every
/// known recency (nothing to rank them by); repo name ascending breaks
/// ties within each group.
int _compareQuiet(PortfolioRepoEntry a, PortfolioRepoEntry b) {
  final aKnown = a.recency is RepoRecencyKnown;
  final bKnown = b.recency is RepoRecencyKnown;
  if (aKnown && bKnown) {
    final aTime = (a.recency as RepoRecencyKnown).lastTouched;
    final bTime = (b.recency as RepoRecencyKnown).lastTouched;
    final ageCmp = bTime.compareTo(aTime); // newer first
    if (ageCmp != 0) return ageCmp;
  } else if (aKnown != bKnown) {
    return aKnown ? -1 : 1;
  }
  return a.name.compareTo(b.name);
}
