/// The Briefing screen (`BU.13.B`) — the app's first tab, answering
/// "what needs me right now?"
///
/// Task 4 (this task) adds the three-stat header — see [BriefingHeader] —
/// per specimen §04. The gates/needs-input lane (task 5) and the
/// blocked-blocks/live-runs lanes (task 6) still land below it in later
/// tasks of this spec, wired through [BriefingViewModel]
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

import '../state/briefing_model.dart';
import '../state/briefing_provider.dart';
import '../widgets/instrument/instrument.dart';

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

/// The Briefing screen body — currently the header (task 4) over a
/// placeholder for the three lanes (tasks 5-6).
class BriefingScreen extends ConsumerWidget {
  const BriefingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewModel = ref.watch(briefingViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Briefing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BriefingHeader(viewModel: viewModel),
              const SizedBox(height: 16),
              const Expanded(
                child: Center(child: Text('Lanes land in BU.13.B tasks 5-6')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
