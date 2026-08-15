/// Dashboard screen — rebuilt as a ranked instrument (`BU.13.D` task 3,
/// specimen `planning/artifacts/from-inventory-to-instrument.html` §05).
///
/// Previously one flat row per workspace-registry repo with a one-word
/// status badge. This task rebuilds it onto `lib/state/portfolio_ranking
/// .dart` (task 2)'s pure tiering: repos are grouped into *needs
/// attention* / *active* / *quiet* [Eyebrow]-headed sections, and each row
/// is a [SeverityRow] whose trailing detail is a [LaneBar] — the
/// proportional done/now/blocked/next bar that replaces the single status
/// word. Task 4 layers an [AgeChip] and a [Sparkline] onto these rows;
/// task 5 collapses the quiet tier and fixes `StatusPill`'s backwards tone
/// mapping (D4 constraint 3). Neither is in scope here.
///
/// ## Data source — reused, not rebuilt
///
/// This screen reads [briefingBoardProvider] (`briefing_provider.dart`,
/// `BU.13.B`) rather than fetching its own `GET /api/board` copy. That
/// provider already calls `api.getBoard(graph: true)` and is a plain
/// root-scope provider (D2), so both the Briefing and Dashboard tabs share
/// one in-flight fetch and one cached result — no second network round
/// trip. `rankPortfolio` itself needs neither `?graph=1`'s
/// `dependentCount`/`ready`/`unmetCount` fields (its gate detection reads
/// `blockedBy`, always on the wire) nor a repo-scoped request (`repos[]`
/// is populated for every scope per serve-api.md §13.3, including the
/// default `scope=hq`) — reuse costs nothing extra here and avoids two
/// screens disagreeing about the same board.
///
/// ## The `now` clock (task 2's determinism contract)
///
/// [rankPortfolio] takes `now` as a required, explicit parameter and never
/// reads the wall clock itself. This screen captures `now` once in
/// [State.initState] — never inside `build` — so a rebuild (a WS event, a
/// pull-to-refresh) does not silently reshuffle tiers out from under the
/// operator's thumb mid-scroll, and so a widget test can construct this
/// screen, override the board provider, and get a deterministic tiering
/// without waiting on the wall clock.
///
/// ## The now-render regression (`BU.ticket.dashboard-now-render`)
///
/// The pre-rebuild screen's guard against rendering the literal `"[]"`
/// sentinel doesn't carry over verbatim — that bug lived in
/// `RepoSummaryDto.now`, a field this screen no longer reads. The
/// underlying discipline does: every row's meta line is built from typed
/// counts (`PortfolioRepoEntry.blockTotal` etc.), never from a raw
/// server-supplied string, so there is no string sentinel left to leak
/// through. `test/screens/dashboard_empty_now_test.dart` (task 3) pins
/// this for the new data shape — a repo with zero blocks renders "0
/// blocks", never `"[]"`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/board_dto.dart';
import '../state/briefing_model.dart';
import '../state/briefing_provider.dart';
import '../state/portfolio_ranking.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/instrument/instrument.dart';

/// Route-name helper for a repo's detail screen (`BU.2.A` Task 5) — kept
/// stable across the rebuild; `RepoDetailScreen`'s route registration in
/// `main.dart` is unchanged by this task.
String repoDetailRouteName(String repoName) => '/repos/$repoName';

/// The accent used for this screen's one interactive affordance (the
/// board section's retry action) — `AppTokens.accent2` per the spec's
/// Accent note (operator decision 2026-08-14), never `AppTokens.primary`.
/// Deliberately a plain, borderless text treatment (mirrors
/// `briefing_screen.dart`'s `_interactiveTextButtonStyle`) so it stays
/// separable from a `StatusPill`'s tinted, bordered chip by shape alone,
/// not colour — `accent2` is also `StatusTones.active`, so "pressable" and
/// "running" cannot be told apart by hue on this screen.
final ButtonStyle _retryButtonStyle = TextButton.styleFrom(
  foregroundColor: AppTokens.accent2,
  textStyle: const TextStyle(fontWeight: FontWeight.w700),
);

/// Live dashboard — repos ranked into needs-attention / active / quiet
/// tiers (`lib/state/portfolio_ranking.dart`), each rendered as a
/// [SeverityRow] with a [LaneBar] trailing detail.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Captured once, in [initState] — never in [build] — so tiering stays
  /// deterministic across rebuilds. See this file's doc comment.
  late final DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(briefingBoardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: _DashboardBody(board: board, now: _now),
      ),
    );
  }
}

/// The screen body, switched on [board]'s independent load state — a
/// loading spinner, an inline error with retry, or the ranked tier list.
class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.board, required this.now});

  final BriefingSectionState<BoardDto> board;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (board.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (board.isError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                board.errorOrNull ?? 'Failed to load.',
                key: const ValueKey('dashboard-error-message'),
                textAlign: TextAlign.center,
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppTokens.inkSoft,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const ValueKey('dashboard-retry'),
                style: _retryButtonStyle,
                onPressed: () =>
                    ref.read(briefingBoardProvider.notifier).reload(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final repos = board.dataOrNull?.repos ?? const [];
    final ranking = rankPortfolio(repos, now: now);

    if (ranking.all.isEmpty) {
      return Center(
        child: Text(
          'No repos registered',
          style: AppTypography.textTheme.bodyMedium?.copyWith(
            color: AppTokens.inkFaint,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(briefingBoardProvider.notifier).reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _DashboardHeading(),
          const SizedBox(height: 16),
          _TierSection(
            label: 'Needs attention',
            entries: ranking.needsAttention,
            now: now,
          ),
          _TierSection(label: 'Active', entries: ranking.active, now: now),
          _QuietTierSection(entries: ranking.quiet, now: now),
        ],
      ),
    );
  }
}

/// This screen's display heading — one [HeadingRule] underneath, per the
/// budget rule (one per screen) `BU.10.C` task 4 established.
class _DashboardHeading extends StatelessWidget {
  const _DashboardHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repositories',
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

/// One tier's [Eyebrow] heading ('Needs attention · 2') plus its ranked
/// repo rows. Renders nothing at all when [entries] is empty — an empty
/// tier gets no heading, so "Active" never shows a "· 0" the operator
/// would have to parse as good news.
class _TierSection extends StatelessWidget {
  const _TierSection({
    required this.label,
    required this.entries,
    required this.now,
  });

  final String label;
  final List<PortfolioRepoEntry> entries;

  /// Threaded straight through to [_RepoRow] — the same clock
  /// [rankPortfolio] used, never re-read here.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label: '$label · ${entries.length}'),
          const SizedBox(height: 10),
          for (final entry in entries) ...[
            _RepoRow(
              key: ValueKey('portfolio-row-${entry.name}'),
              entry: entry,
              now: now,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// The quiet tier's section: an [Eyebrow] heading identical to
/// [_TierSection]'s, but with its rows collapsed by default into a single
/// tappable summary row (task 5) rather than always rendering every quiet
/// repo. Quiet repos are, by definition, the ones with nothing in flight
/// and nothing blocked — the tier the operator least needs a full list of
/// on every load — so this is the one tier whose rows are opt-in.
///
/// State (`_expanded`) lives on this widget, not a provider — the spec's
/// task 5 note is explicit that this needs no new provider, and the
/// expand/collapse choice does not need to survive a screen rebuild or a
/// navigation round trip.
class _QuietTierSection extends StatefulWidget {
  const _QuietTierSection({required this.entries, required this.now});

  final List<PortfolioRepoEntry> entries;
  final DateTime now;

  @override
  State<_QuietTierSection> createState() => _QuietTierSectionState();
}

class _QuietTierSectionState extends State<_QuietTierSection> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label: 'Quiet · ${entries.length}'),
          const SizedBox(height: 10),
          if (_expanded) ...[
            for (final entry in entries) ...[
              _RepoRow(
                key: ValueKey('portfolio-row-${entry.name}'),
                entry: entry,
                now: widget.now,
              ),
              const SizedBox(height: 8),
            ],
            _QuietCollapseRow(onTap: _toggle),
          ] else
            _QuietSummaryRow(
              key: const ValueKey('portfolio-quiet-toggle'),
              entries: entries,
              onTap: _toggle,
            ),
        ],
      ),
    );
  }
}

/// The quiet tier's collapsed state: one row naming the first three quiet
/// repos ('bella · price-scout · mev-docs') plus a `+N` count for the
/// rest, per specimen §05. Tapping (anywhere on the row) expands the tier.
class _QuietSummaryRow extends StatelessWidget {
  const _QuietSummaryRow({super.key, required this.entries, this.onTap});

  final List<PortfolioRepoEntry> entries;
  final VoidCallback? onTap;

  /// The first three quiet repo names joined by ` · `, plus a `+N` suffix
  /// naming how many more are collapsed underneath — never a bare count
  /// with no names, and never all names once there are more than three
  /// (the row must stay one line on a phone width).
  static const int _namedCount = 3;

  String get _summaryText {
    final named = entries.take(_namedCount).map((e) => e.name).join(' · ');
    final remaining = entries.length - _namedCount;
    return remaining > 0 ? '$named  +$remaining' : named;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('portfolio-quiet-summary-tap'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: AppTokens.line, width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _summaryText,
                key: const ValueKey('portfolio-quiet-summary-text'),
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppTokens.inkSoft,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.expand_more,
              key: const ValueKey('portfolio-quiet-expand-icon'),
              size: 18,
              color: AppTokens.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet tier's expanded-state footer: a plain tap target that
/// collapses the tier again, so the operator never has to scroll back up
/// to the [Eyebrow] to put the tier away.
class _QuietCollapseRow extends StatelessWidget {
  const _QuietCollapseRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('portfolio-quiet-collapse'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Collapse',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppTokens.inkFaint,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_less, size: 18, color: AppTokens.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// One repo row: a [SeverityRow] (severity stripe + `StatusPill` + meta
/// line) with a [LaneBar] trailing detail, per specimen §05's `cardline`.
class _RepoRow extends StatelessWidget {
  const _RepoRow({super.key, required this.entry, required this.now});

  final PortfolioRepoEntry entry;

  /// The same clock [rankPortfolio] tiered against (captured once in
  /// [_DashboardScreenState.initState]) — feeds [AgeChip.since] and
  /// [_recentActivityValues] so a rebuild never reshuffles either
  /// mid-scroll (task 2's determinism contract, task 4 AC).
  final DateTime now;

  /// The row's severity — drives the stripe colour and the title's
  /// non-colour weight channel. A blocked or gated repo reads `crit`; a
  /// repo that landed in needs-attention purely via the drift-promotion
  /// rule (nothing blocked, nothing gated, just stale) reads the calmer
  /// `warn` — it needs attention, but it is not on fire.
  SeverityRowSeverity get _severity => switch (entry.tier) {
    PortfolioTier.needsAttention =>
      entry.blockedCount > 0
          ? SeverityRowSeverity.crit
          : SeverityRowSeverity.warn,
    PortfolioTier.active => SeverityRowSeverity.ok,
    PortfolioTier.quiet => SeverityRowSeverity.idle,
  };

  /// The trailing `StatusPill`'s tone + label, one per tier per specimen
  /// §05 ("2 GATES" / "STALE 9d" / "RUNNING" / "ON TRACK").
  ///
  /// **D4 constraint 3 (task 5).** The web-ported tone table names
  /// `StatusPillTone.onTrack` -> `tones.active` (the loud, `accent2`
  /// tone) and `StatusPillTone.inProgress` -> `tones.neutral` (the muted
  /// tone) — see `status_pill.dart`'s `statusToneFor`. Before this task,
  /// the *active* tier ("RUNNING") was assigned `inProgress` (muted) while
  /// the *quiet* tier ("ON TRACK") was assigned `onTrack` (loud): the calm
  /// state read louder than the running one, inverting principle 2. This
  /// repo owns the repo->pill mapping (not `statusToneFor` itself, which
  /// other screens' own mappings rely on), so the fix is here: swap which
  /// of the four fixed tones each tier's pill uses, re-mapping within the
  /// existing four rather than adding a fifth (`StatusPillTone` is an
  /// exhaustive four-case enum by design, `status_pill.dart:37-44`).
  (StatusPillTone, String) get _pill {
    switch (entry.tier) {
      case PortfolioTier.needsAttention:
        if (entry.blockedCount > 0) {
          return entry.hasOpenGate
              ? (StatusPillTone.needsYou, '${entry.blockedCount} GATES')
              : (StatusPillTone.blocked, '${entry.blockedCount} BLOCKED');
        }
        return (StatusPillTone.needsYou, 'STALE');
      case PortfolioTier.active:
        // Loud: an active repo must read louder than an idle one.
        return (StatusPillTone.onTrack, 'RUNNING');
      case PortfolioTier.quiet:
        // Muted: the calm state no longer outshines the running one.
        return (StatusPillTone.inProgress, 'ON TRACK');
    }
  }

  /// The meta sub-line — always leads with the repo's total block count,
  /// then a tier-appropriate qualifier. Built entirely from typed counts,
  /// never a raw server string (see this file's now-render doc comment).
  String get _meta {
    final total = entry.blockTotal;
    switch (entry.tier) {
      case PortfolioTier.needsAttention:
        return entry.blockedCount > 0
            ? '$total blocks · ${entry.blockedCount} blocked'
            : '$total blocks · nothing in flight';
      case PortfolioTier.active:
        return '$total blocks · ${entry.nowCount} in flight';
      case PortfolioTier.quiet:
        return '$total blocks · nothing in flight, nothing blocked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final (pillTone, pillLabel) = _pill;

    // The `LaneBar`'s four segment counts must sum to the repo's block
    // total minus `deferred` (deferred is tracked on `blockTotal` but is
    // not one of the bar's four segments — see `PortfolioRepoEntry
    // .blockTotal`'s doc comment). A bar that silently dropped a lane
    // would misrepresent the repo, so this is asserted rather than merely
    // assumed; only runs in debug/test builds.
    assert(
      () {
        final barTotal =
            entry.doneCount +
            entry.nowCount +
            entry.blockedCount +
            entry.nextCount;
        final expected = entry.blockTotal - entry.deferredCount;
        return barTotal == expected;
      }(),
      'LaneBar segment counts must sum to the repo block total (minus deferred)',
    );

    final activity = _recentActivityValues(entry.repo, now);

    return InkWell(
      key: ValueKey('portfolio-row-tap-${entry.name}'),
      onTap: () =>
          Navigator.of(context).pushNamed(repoDetailRouteName(entry.name)),
      child: SeverityRow(
        severity: _severity,
        title: entry.name,
        pillTone: pillTone,
        pillLabel: pillLabel,
        meta: _meta,
        trailingDetail: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LaneBar(
                    done: entry.doneCount,
                    now: entry.nowCount,
                    blocked: entry.blockedCount,
                    next: entry.nextCount,
                  ),
                ),
                const SizedBox(width: 8),
                _RecencyIndicator(
                  key: ValueKey('portfolio-recency-${entry.name}'),
                  recency: entry.recency,
                  now: now,
                ),
              ],
            ),
            // A repo with no touches in the tracked window renders no
            // sparkline at all — a flat row of zero-height bars would read
            // as "measured and idle" rather than "no data" (task 4 AC).
            if (activity.isNotEmpty) ...[
              const SizedBox(height: 8),
              Sparkline(
                key: ValueKey('portfolio-sparkline-${entry.name}'),
                values: activity,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The recency slot beside the `LaneBar`: an [AgeChip] for a
/// [RepoRecencyKnown] repo, or an honest "not started" treatment for
/// [RepoRecencyNeverWorked] — never a fabricated age, and never an em dash
/// standing in for one (task 4 AC; preserves task 1/2's never-worked vs.
/// stale distinction to the pixel).
class _RecencyIndicator extends StatelessWidget {
  const _RecencyIndicator({
    super.key,
    required this.recency,
    required this.now,
  });

  final RepoRecency recency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final recency = this.recency;
    if (recency is RepoRecencyKnown) {
      return AgeChip.since(recency.lastTouched, now: now);
    }

    final tone = context.statusTones.neutral;
    return Container(
      key: const ValueKey('portfolio-recency-not-started'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        border: Border.all(color: tone.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Text(
        'not started',
        style: AppTypography.textTheme.labelSmall?.copyWith(
          color: tone.foreground,
        ),
      ),
    );
  }
}

/// The default window for [_recentActivityValues]: the last 7 days
/// (specimen `from-inventory-to-instrument.html` §05's seven-bar
/// `Sparkline`, "activity over the last seven days").
const int _kActivityWindowDays = 7;

/// Derives [entry]'s `Sparkline` series from the real, already-served
/// `lastTouched` timestamps on its blocks — never a fabricated or
/// synthetic count. Buckets every block's `lastTouched` into the day it
/// fell on within the trailing [_kActivityWindowDays]-day window (oldest
/// first, so the series reads left-to-right as a trajectory), and returns
/// the empty list — not a flat row of zeroes — when nothing in [repo] was
/// touched inside that window, so [_RepoRow] can render no `Sparkline` at
/// all for a repo with no recent activity (task 4 AC).
///
/// Pure: takes [now] explicitly and never reads the wall clock, matching
/// task 2's determinism contract for this screen.
List<double> _recentActivityValues(RepoBoardDto repo, DateTime now) {
  final counts = List<double>.filled(_kActivityWindowDays, 0);
  final today = DateTime(now.year, now.month, now.day);
  final allBlocks = [
    ...repo.lanes.now,
    ...repo.lanes.next,
    ...repo.lanes.blocked,
    ...repo.lanes.deferred,
    ...repo.lanes.finished,
  ];

  var hasActivity = false;
  for (final block in allBlocks) {
    final touched = block.lastTouched;
    if (touched == null) continue;
    final touchedDay = DateTime(touched.year, touched.month, touched.day);
    final daysAgo = today.difference(touchedDay).inDays;
    if (daysAgo < 0 || daysAgo >= _kActivityWindowDays) continue;
    counts[_kActivityWindowDays - 1 - daysAgo] += 1;
    hasActivity = true;
  }

  return hasActivity ? counts : const [];
}
