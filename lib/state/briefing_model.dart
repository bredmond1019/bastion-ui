/// Pure, widget-free view model for the Briefing screen (`BU.13.B`).
///
/// This file has ZERO Flutter imports — it is plain Dart operating on the
/// already-decoded wire DTOs (`BoardBlockDto`, `AttentionCarryoverDto`,
/// `SessionDto`). `lib/screens/briefing_screen.dart` renders it;
/// `lib/state/briefing_provider.dart` (task 3) fetches the three data
/// sources and produces it.
///
/// ## Section shape
///
/// The screen draws from three data sources — `GET /api/board`,
/// `GET /api/attention`, and the live sessions list — and each one must be
/// able to fail without blanking the other two. [BriefingSectionState]
/// models that: a section is independently `loading`, `loaded`, or `error`.
/// [BriefingViewModel] carries exactly three of these ([board], [attention],
/// [sessions]) — NOT one shared loading flag for the whole screen.
///
/// ## Header counts
///
/// The three header stats (needs-you / blocked / running) are computed
/// getters over the SAME ranked lists the lanes render
/// ([BriefingViewModel.rankedGates] + [BriefingViewModel.rankedNeedsInput],
/// [BriefingViewModel.rankedBlockedBlocks], [BriefingViewModel.liveRuns]) —
/// never a separately-counted number. That is deliberate: a header stat
/// computed from a different path than the list beneath it can disagree
/// with it, and this screen's whole premise is "the header is trustworthy."
///
/// ## Null / nulls-sort-last convention
///
/// `dependent_count` and `age_days` are both nullable on the wire — `null`
/// means "not known" (e.g. `dependent_count` requires `?graph=true`; a
/// carryover entry can be snoozed / anchor-less). Treating `null` as `0` in
/// a descending sort would rank an unknown gate/block ABOVE known-lesser
/// ones, silently asserting a fact the app does not have. Both ranking
/// functions below sort known values first (descending), and push `null`
/// values to the end, ordered among themselves by their deterministic
/// tie-break key.
library;

import '../models/attention_dto.dart';
import '../models/board_dto.dart';
import '../models/session_dto.dart';

// ---------------------------------------------------------------------------
// BriefingSectionState — independent loading/loaded/error per data source
// ---------------------------------------------------------------------------

/// The load state of one of the Briefing's three independent data sources.
///
/// Deliberately NOT a single screen-wide `isLoading`/`error` pair — each
/// section (board / attention / sessions) carries its own, so one endpoint
/// failing degrades only its own section.
sealed class BriefingSectionState<T> {
  const BriefingSectionState();

  /// The loaded payload, or `null` if this section is loading or errored.
  T? get dataOrNull => switch (this) {
    BriefingSectionLoaded<T>(:final data) => data,
    _ => null,
  };

  bool get isLoading => this is BriefingSectionLoading<T>;

  bool get isError => this is BriefingSectionError<T>;

  /// The error message, or `null` if this section is not in an error state.
  String? get errorOrNull => switch (this) {
    BriefingSectionError<T>(:final message) => message,
    _ => null,
  };
}

/// The section's initial/in-flight state — no data yet, no error yet.
final class BriefingSectionLoading<T> extends BriefingSectionState<T> {
  const BriefingSectionLoading();
}

/// The section's fetch succeeded; [data] is the decoded payload.
final class BriefingSectionLoaded<T> extends BriefingSectionState<T> {
  final T data;

  const BriefingSectionLoaded(this.data);
}

/// The section's fetch failed; [message] is a display-ready description.
/// Other sections are unaffected — this is the whole point of modelling
/// three independent states rather than one shared one.
final class BriefingSectionError<T> extends BriefingSectionState<T> {
  final String message;

  const BriefingSectionError(this.message);
}

// ---------------------------------------------------------------------------
// NeedsInputSessionEntry — a session flagged needs_input, with its idle time
// ---------------------------------------------------------------------------

/// A session currently flagged `needs_input`, paired with how long it has
/// been waiting.
///
/// `SessionDto` itself carries no timestamp (serve-api §10 is a snapshot,
/// not an activity log), so idle time is not decodable from the DTO alone.
/// [briefing_provider.dart] (task 3) is responsible for tracking "since
/// when" a session has been flagged (from the `needs_input` WS event's
/// arrival) and supplying it here. [idle] is nullable for the same reason
/// [dependentCount]/[ageDays] are: "not yet known" must never be silently
/// treated as "zero idle time," which would wrongly rank a fresh flag as
/// the most urgent.
final class NeedsInputSessionEntry {
  final SessionDto session;
  final Duration? idle;

  const NeedsInputSessionEntry({required this.session, this.idle});
}

// ---------------------------------------------------------------------------
// Ranking — pure functions over already-decoded DTOs
// ---------------------------------------------------------------------------

/// Descending comparison for a nullable `int` where `null` sorts LAST
/// (least urgent), never as `0`. Ties (including both-null) are `0` — the
/// caller supplies the deterministic tie-break.
int compareNullableIntDescNullsLast(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// Descending comparison for a nullable [Duration] where `null` sorts LAST,
/// mirroring [compareNullableIntDescNullsLast].
int compareNullableDurationDescNullsLast(Duration? a, Duration? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// Operator gates: `BoardBlockDto`s from the board's `blocked` lane whose
/// `blocked_by` includes an operator- or approval-type dependency — the
/// two `BlockedByDto` variants that name an operator action as the thing
/// standing in the way, as opposed to another block or an external
/// dependency.
///
/// Ranked by `dependent_count` descending (blast radius: how much unblocks
/// when this gate clears), `null` sorting last per the module doc. Ties
/// (including both-null) break on `id` ascending, so order is stable
/// across rebuilds regardless of fetch/JSON-map ordering.
List<BoardBlockDto> rankOperatorGates(List<BoardBlockDto> blockedLane) {
  final gates = blockedLane
      .where(
        (b) =>
            b.blockedBy.any((d) => d is OperatorDepDto || d is ApprovalDepDto),
      )
      .toList();
  gates.sort((a, b) {
    final cmp = compareNullableIntDescNullsLast(
      a.dependentCount,
      b.dependentCount,
    );
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });
  return gates;
}

/// Needs-input sessions ranked by idle time descending (longest-waiting
/// first — the operator's attention is most overdue there), `null` idle
/// (not yet tracked) sorting last. Ties break on session name ascending.
List<NeedsInputSessionEntry> rankNeedsInputSessions(
  List<NeedsInputSessionEntry> entries,
) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final cmp = compareNullableDurationDescNullsLast(a.idle, b.idle);
    if (cmp != 0) return cmp;
    return a.session.name.compareTo(b.session.name);
  });
  return sorted;
}

/// Blocked-block carryover entries — the `stale_carryover` items whose
/// `lane` is `"blocking"` (mev's own triage lane for a carryover with
/// unmet `blocks[]` edges; never re-derived client-side, per
/// `AttentionCarryoverDto.lane`'s doc comment) — ranked by `age_days`
/// descending, `null` (snoozed / anchor-less) sorting last. Ties break on
/// `slug` ascending.
List<AttentionCarryoverDto> rankBlockedBlocks(
  List<AttentionCarryoverDto> staleCarryover,
) {
  final blocked = staleCarryover.where((c) => c.lane == 'blocking').toList();
  blocked.sort((a, b) {
    final cmp = compareNullableIntDescNullsLast(a.ageDays, b.ageDays);
    if (cmp != 0) return cmp;
    return a.slug.compareTo(b.slug);
  });
  return blocked;
}

/// Live (running, not needs-input) sessions for lane 3. No ranking beyond a
/// stable name-ascending order is specified for this lane.
List<SessionDto> rankLiveRuns(List<SessionDto> sessions) {
  final running = sessions
      .where((s) => s.state == 'running' && s.agentState != AgentState.blocked)
      .toList();
  running.sort((a, b) => a.name.compareTo(b.name));
  return running;
}

// ---------------------------------------------------------------------------
// BriefingViewModel
// ---------------------------------------------------------------------------

/// The full, widget-free shape the Briefing screen renders: three
/// independently-stated sections plus the ranked lanes and header counts
/// derived from them.
final class BriefingViewModel {
  /// `GET /api/board` section (drives operator gates + blocked blocks'
  /// "waiting on" framing via its `blocked` lane).
  final BriefingSectionState<BoardDto> board;

  /// `GET /api/attention` section (drives the blocked-blocks lane via its
  /// `stale_carryover` lane).
  final BriefingSectionState<AttentionDto> attention;

  /// Live sessions section, plus the idle time tracked for each
  /// `needs_input`-flagged session (see [NeedsInputSessionEntry]).
  final BriefingSectionState<List<SessionDto>> sessions;

  /// Idle duration for sessions currently flagged `needs_input`, keyed by
  /// session name. Absent entries (session flagged but no tracked idle
  /// time yet) rank last per [rankNeedsInputSessions] via a `null` idle.
  final Map<String, Duration> needsInputIdle;

  const BriefingViewModel({
    this.board = const BriefingSectionLoading(),
    this.attention = const BriefingSectionLoading(),
    this.sessions = const BriefingSectionLoading(),
    this.needsInputIdle = const {},
  });

  /// Operator gates, ranked. Empty (never throws) while [board] is loading
  /// or errored.
  List<BoardBlockDto> get rankedGates {
    final data = board.dataOrNull;
    if (data == null) return const [];
    return rankOperatorGates(data.lanes.blocked);
  }

  /// Needs-input sessions, ranked. Empty while [sessions] is loading or
  /// errored.
  List<NeedsInputSessionEntry> get rankedNeedsInput {
    final data = sessions.dataOrNull;
    if (data == null) return const [];
    final flagged = data.where((s) => s.agentState == AgentState.blocked);
    final entries = flagged
        .map(
          (s) =>
              NeedsInputSessionEntry(session: s, idle: needsInputIdle[s.name]),
        )
        .toList();
    return rankNeedsInputSessions(entries);
  }

  /// Blocked blocks, ranked. Empty while [attention] is loading or errored.
  List<AttentionCarryoverDto> get rankedBlockedBlocks {
    final data = attention.dataOrNull;
    if (data == null) return const [];
    return rankBlockedBlocks(data.lanes.staleCarryover);
  }

  /// Live runs for lane 3. Empty while [sessions] is loading or errored.
  List<SessionDto> get liveRuns {
    final data = sessions.dataOrNull;
    if (data == null) return const [];
    return rankLiveRuns(data);
  }

  /// Header stat: "needs you" — operator gates plus needs-input sessions,
  /// computed from the SAME lists lane 1 renders (never a separate count).
  int get needsYouCount => rankedGates.length + rankedNeedsInput.length;

  /// Header stat: "blocked" — same list lane 2 renders.
  int get blockedCount => rankedBlockedBlocks.length;

  /// Header stat: "running" — same list lane 3 renders.
  int get runningCount => liveRuns.length;
}
