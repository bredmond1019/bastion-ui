/// The Briefing screen (`BU.13.B`) — the app's first tab, answering
/// "what needs me right now?"
///
/// Task 4 added the three-stat header — see [BriefingHeader] — per specimen
/// §04. Task 5 (this task) adds lane 1 — see [BriefingGatesLane] — the
/// screen's ONE primary action (principle 5). Lanes 2/3 (blocked blocks,
/// live runs) still land below it in task 6, wired through
/// [BriefingViewModel] (`lib/state/briefing_model.dart`, task 1) and
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

import '../models/board_dto.dart';
import '../state/briefing_model.dart';
import '../state/briefing_provider.dart';
import '../widgets/brand/status_pill.dart';
import '../widgets/instrument/instrument.dart';
import 'dashboard_screen.dart' show repoDetailRouteName;

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

  @override
  Widget build(BuildContext context) {
    final gates = viewModel.rankedGates;
    final needsInput = viewModel.rankedNeedsInput;

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

/// The Briefing screen body — the header (task 4) over lane 1 (task 5, this
/// task) over a placeholder for lanes 2/3 (task 6).
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
              ),
              const SizedBox(height: 16),
              const Center(child: Text('Lanes 2-3 land in BU.13.B task 6')),
            ],
          ),
        ),
      ),
    );
  }
}
