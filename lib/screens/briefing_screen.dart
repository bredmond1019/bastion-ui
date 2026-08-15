/// The Briefing screen (`BU.13.B`) — the app's first tab, answering
/// "what needs me right now?"
///
/// Task 4 added the three-stat header — see [BriefingHeader] — per specimen
/// §04. Task 5 added lane 1 — see [BriefingGatesLane] — the screen's ONE
/// primary action (principle 5). Task 6 (this task) adds lanes 2/3 — see
/// [BriefingBlockedLane] and [BriefingLiveRunsLane] — and gives all three
/// lanes an independent inline error state with a retry action, so one
/// failing data source degrades only its own lane rather than blanking the
/// screen (this block's core risk — see `lib/state/briefing_provider.dart`'s
/// doc comment). Every lane is wired through [BriefingViewModel]
/// (`lib/state/briefing_model.dart`, task 1) and
/// `lib/state/briefing_provider.dart` (task 3).
///
/// Wiring this screen into [HomeShell] as the FIRST tab was task 2's job
/// (`BU.13.B` task 2, deliberately run second rather than last) — this
/// repo has twice shipped UI that existed and was unit-tested but was never
/// reachable from the running app (`BU.1.A`, `ticket-brand-header-lockup`).
/// See `test/screens/briefing_reachable_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attention_dto.dart';
import '../models/board_dto.dart';
import '../state/briefing_model.dart';
import '../state/briefing_provider.dart';
import '../theme/tokens.dart';
import '../widgets/brand/status_pill.dart';
import '../widgets/instrument/instrument.dart';
import 'dashboard_screen.dart' show repoDetailRouteName;

/// No-op default for a lane's `onRetry` when a caller (e.g. an existing
/// test fixture built before this task) does not supply one — a lane whose
/// section never errors in practice (see [BriefingGatesLane]'s pre-task-6
/// callers) should not be forced to thread a retry callback it will never
/// use.
void _noRetry() {}

/// A lane's inline error state — a short message identifying which section
/// failed, plus a retry action. Distinct from a lane's empty state
/// ([_LaneEmptyState]): an error is bad news requiring action, an empty
/// lane is good news requiring none. [laneId] namespaces the widget keys so
/// three lanes can render simultaneously without colliding `ValueKey`s.
class _LaneErrorState extends StatelessWidget {
  const _LaneErrorState({
    required this.laneId,
    required this.message,
    required this.onRetry,
  });

  final String laneId;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('briefing-lane-error-$laneId'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              key: ValueKey('briefing-lane-error-message-$laneId'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: ValueKey('briefing-lane-retry-$laneId'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// A lane's empty state — a calm "nothing here" message, deliberately
/// styled and keyed distinctly from [_LaneErrorState]: an empty blocked
/// lane or an empty live-runs lane is good news, not a failure, and must
/// never be mistaken for one.
class _LaneEmptyState extends StatelessWidget {
  const _LaneEmptyState({required this.laneId, required this.message});

  final String laneId;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('briefing-lane-empty-$laneId'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        key: ValueKey('briefing-lane-empty-message-$laneId'),
        style: const TextStyle(color: AppTokens.inkFaint),
      ),
    );
  }
}

/// The Briefing's three-stat header: needs-you / blocked / running, one
/// [StatTile] each, in that order — the order the header stats are
/// enumerated in `BriefingViewModel`'s doc comment and matches consequence
/// (principle 2: rank by consequence), needs-you outranking blocked
/// outranking running.
///
/// A plain [StatelessWidget] taking an already-resolved [viewModel] rather
/// than watching a provider itself, so it can be unit-tested with a bare
/// [BriefingViewModel] fixture (`test/screens/briefing_header_test.dart`)
/// with no Riverpod/HTTP wiring required.
class BriefingHeader extends StatelessWidget {
  const BriefingHeader({super.key, required this.viewModel});

  final BriefingViewModel viewModel;

  /// `StatTile.value` is a pre-formatted `String` — this screen owns
  /// formatting. Renders an em dash, never `"0"`, when the section(s) a
  /// stat is computed from errored: a `"0"` would assert a fact the app
  /// does not have (that section truly has zero items), when in fact the
  /// count is simply unknown.
  static String _format(int count, {required bool unknown}) {
    return unknown ? '—' : '$count';
  }

  @override
  Widget build(BuildContext context) {
    // needsYouCount sums operator gates (from `board`) and needs-input
    // sessions (from `sessions`) — either source erroring makes the total
    // unknown, not partially-known-as-a-smaller-number.
    final needsYouUnknown =
        viewModel.board.isError || viewModel.sessions.isError;
    final blockedUnknown = viewModel.attention.isError;
    final runningUnknown = viewModel.sessions.isError;

    // `IntrinsicHeight` bounds the row to its tallest child's natural
    // height before `CrossAxisAlignment.stretch` applies — without it, a
    // `Row` that stretches its children needs a bounded incoming height,
    // and as a plain (non-`Expanded`) child of `BriefingScreen`'s `Column`
    // it would otherwise receive an unbounded (loose 0..infinity) height
    // constraint and hit "BoxConstraints forces an infinite height".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(
              value: _format(viewModel.needsYouCount, unknown: needsYouUnknown),
              label: 'need you',
              severity: StatTileSeverity.danger,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: _format(viewModel.blockedCount, unknown: blockedUnknown),
              label: 'blocked',
              severity: StatTileSeverity.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: _format(viewModel.runningCount, unknown: runningUnknown),
              label: 'running',
              severity: StatTileSeverity.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lane 1 — operator gates (as [GateCard]s, ranked by blast radius) then
/// needs-input sessions (as [SeverityRow]s, ranked by idle time) — the
/// screen's ONE primary action (principle 5, specimen §04). It renders
/// first, above lanes 2/3 (`BU.13.B` task 6), and is visually the most
/// prominent thing on the screen: full-width [GateCard]s rather than the
/// compact rows lanes 2/3 use.
///
/// Like [BriefingHeader], takes an already-resolved [viewModel] rather than
/// watching a provider, so it is unit-testable
/// (`test/screens/briefing_gates_test.dart`) with a bare
/// [BriefingViewModel] fixture and no Riverpod/HTTP wiring. [now] is
/// threaded explicitly through to every [AgeChip.since] call — the widget
/// itself never calls `DateTime.now()` in [build], so a test can pin an
/// age deterministically.
class BriefingGatesLane extends StatelessWidget {
  const BriefingGatesLane({
    super.key,
    required this.viewModel,
    required this.now,
    required this.onGateAct,
    this.onRetry = _noRetry,
  });

  final BriefingViewModel viewModel;

  /// Threaded into [AgeChip.since] for every needs-input row rather than
  /// read from the wall clock inside [build].
  final DateTime now;

  /// Fired when the operator taps a gate's primary action. The caller
  /// decides what "act" means (`GateCard.onAct` may navigate or open an
  /// existing sheet; this lane invents no new write path) — see
  /// [BriefingScreen]'s wiring, which pushes the gate's repo detail route.
  final void Function(BoardBlockDto gate) onGateAct;

  /// Fired when the operator taps "Retry" on this lane's error state
  /// (task 6). Optional — defaults to a no-op so callers built before task
  /// 6 (e.g. `test/screens/briefing_gates_test.dart`, task 5) keep
  /// compiling unchanged.
  final VoidCallback onRetry;

  /// What a gate is waiting on, in one short phrase: the first
  /// operator/approval dependency's `what`, falling back to a description
  /// naming the operator slug when `what` is absent (operator deps only —
  /// approval deps' `what` is non-nullable). [rankOperatorGates] only ever
  /// produces gates carrying at least one such dependency, but this
  /// degrades to a generic phrase rather than throwing if that ever
  /// changes upstream.
  static String _waitingOn(BoardBlockDto gate) {
    for (final dep in gate.blockedBy) {
      if (dep is OperatorDepDto) {
        return dep.what ?? 'operator session ${dep.slug}';
      }
      if (dep is ApprovalDepDto) return dep.what;
    }
    return 'operator action';
  }

  /// This lane's error message, or `null` if neither of its two data
  /// sources (board → gates, sessions → needs-input) is currently errored.
  ///
  /// Board is checked first: gate ranking is the lane's ONE primary action
  /// (principle 5), so a board failure is surfaced ahead of a sessions
  /// failure even if both happen to be errored at once. Without this, a
  /// board error would silently render as "no gates" via
  /// [BriefingViewModel.rankedGates]'s empty-on-error fallback — a calm
  /// empty state asserting a fact ("nothing needs you") the app does not
  /// actually have.
  String? _errorMessage() {
    if (viewModel.board.isError) return viewModel.board.errorOrNull;
    if (viewModel.sessions.isError) return viewModel.sessions.errorOrNull;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _errorMessage();
    if (error != null) {
      return _LaneErrorState(laneId: 'gates', message: error, onRetry: onRetry);
    }

    final gates = viewModel.rankedGates;
    final needsInput = viewModel.rankedNeedsInput;

    if (gates.isEmpty && needsInput.isEmpty) {
      return const _LaneEmptyState(
        laneId: 'gates',
        message: 'Nothing needs you right now.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final gate in gates) ...[
          GateCard(
            name: gate.title,
            waitingOn: _waitingOn(gate),
            blastRadius: gate.dependentCount,
            onAct: () => onGateAct(gate),
          ),
          const SizedBox(height: 10),
        ],
        for (final entry in needsInput) ...[
          SeverityRow(
            severity: SeverityRowSeverity.crit,
            title: entry.session.name,
            pillTone: StatusPillTone.needsYou,
            pillLabel: 'NEEDS INPUT',
            meta: entry.session.lastLine ?? 'waiting for input',
            trailingDetail: entry.idle == null
                ? null
                : AgeChip.since(now.subtract(entry.idle!), now: now),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Lane 2 — blocked blocks (`BU.13.B` task 6): the `attention` section's
/// `stale_carryover` entries whose triage lane is `"blocking"`, ranked by
/// `age_days` descending (task 1's [BriefingViewModel.rankedBlockedBlocks]),
/// each rendered as a [SeverityRow] naming what it is waiting on.
///
/// Independently stated from lanes 1/3: an [viewModel.attention] error
/// renders this lane's own inline error + retry without affecting the
/// gates/needs-input lane above it or the live-runs lane below it — the
/// spec's core risk (see this file's doc comment).
class BriefingBlockedLane extends StatelessWidget {
  const BriefingBlockedLane({
    super.key,
    required this.viewModel,
    this.onRetry = _noRetry,
  });

  final BriefingViewModel viewModel;

  /// Fired when the operator taps "Retry" on this lane's error state.
  final VoidCallback onRetry;

  /// What a blocked block is waiting on, in one short phrase: its unmet
  /// `blocks[]` edges (non-empty by construction for a `"blocking"`-lane
  /// entry — see `AttentionCarryoverDto.unmetBlocks`'s doc comment), falling
  /// back to the carryover's own text if that ever comes back empty.
  static String _waitingOn(AttentionCarryoverDto carryover) {
    if (carryover.unmetBlocks.isNotEmpty) {
      return 'waiting on ${carryover.unmetBlocks.join(', ')}';
    }
    return carryover.text;
  }

  static String _pillLabel(AttentionCarryoverDto carryover) {
    final age = carryover.ageDays;
    return age == null ? 'STALE' : 'STALE ${age}d';
  }

  @override
  Widget build(BuildContext context) {
    if (viewModel.attention.isError) {
      return _LaneErrorState(
        laneId: 'blocked',
        message: viewModel.attention.errorOrNull ?? 'Failed to load.',
        onRetry: onRetry,
      );
    }

    final blocked = viewModel.rankedBlockedBlocks;
    if (blocked.isEmpty) {
      return const _LaneEmptyState(
        laneId: 'blocked',
        message: 'Nothing blocked — clear runway.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final carryover in blocked) ...[
          SeverityRow(
            severity: SeverityRowSeverity.warn,
            title: '${carryover.repo}/${carryover.slug}',
            pillTone: StatusPillTone.blocked,
            pillLabel: _pillLabel(carryover),
            meta: _waitingOn(carryover),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Lane 3 — live runs (`BU.13.B` task 6): running, non-needs-input sessions
/// (task 1's [BriefingViewModel.liveRuns]), each rendered as a calm
/// [SeverityRow].
///
/// Independently stated from lanes 1/2: a [viewModel.sessions] error
/// renders this lane's own inline error + retry without affecting the two
/// lanes above it.
class BriefingLiveRunsLane extends StatelessWidget {
  const BriefingLiveRunsLane({
    super.key,
    required this.viewModel,
    this.onRetry = _noRetry,
  });

  final BriefingViewModel viewModel;

  /// Fired when the operator taps "Retry" on this lane's error state.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (viewModel.sessions.isError) {
      return _LaneErrorState(
        laneId: 'live-runs',
        message: viewModel.sessions.errorOrNull ?? 'Failed to load.',
        onRetry: onRetry,
      );
    }

    final running = viewModel.liveRuns;
    if (running.isEmpty) {
      return const _LaneEmptyState(
        laneId: 'live-runs',
        message: 'Nothing running right now.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final session in running) ...[
          SeverityRow(
            severity: SeverityRowSeverity.idle,
            title: session.name,
            pillTone: StatusPillTone.onTrack,
            pillLabel: 'RUNNING',
            meta: session.lastLine ?? 'running',
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// The Briefing screen body — the header (task 4) over lane 1 (task 5) over
/// lanes 2/3 (task 6, this task), each lane independently stated so one
/// failing data source degrades only its own section.
class BriefingScreen extends ConsumerWidget {
  const BriefingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.watch(briefingViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Briefing')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BriefingHeader(viewModel: viewModel),
              const SizedBox(height: 16),
              BriefingGatesLane(
                viewModel: viewModel,
                now: DateTime.now(),
                onGateAct: (gate) => Navigator.of(
                  context,
                ).pushNamed(repoDetailRouteName(gate.repo)),
                onRetry: () =>
                    ref.read(briefingBoardProvider.notifier).reload(),
              ),
              const SizedBox(height: 16),
              BriefingBlockedLane(
                viewModel: viewModel,
                onRetry: () =>
                    ref.read(briefingAttentionProvider.notifier).reload(),
              ),
              const SizedBox(height: 16),
              BriefingLiveRunsLane(viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }
}
