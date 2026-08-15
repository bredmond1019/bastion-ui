/// The Briefing screen (`BU.13.B`) — the app's first tab, answering
/// "what needs me right now?"
///
/// This file is deliberately minimal for now: a scaffold + title only. The
/// three-stat header (task 4), the gates/needs-input lane (task 5), and the
/// blocked-blocks/live-runs lanes (task 6) land in later tasks of this spec,
/// wired through [BriefingViewModel] (`lib/state/briefing_model.dart`, task
/// 1) and `lib/state/briefing_provider.dart` (task 3).
///
/// Wiring this screen into [HomeShell] as the FIRST tab is this task's whole
/// job (`BU.13.B` task 2, deliberately run second rather than last) — this
/// repo has twice shipped UI that existed and was unit-tested but was never
/// reachable from the running app (`BU.1.A`, `ticket-brand-header-lockup`).
/// See `test/screens/briefing_reachable_test.dart`.
library;

import 'package:flutter/material.dart';

/// Minimal placeholder body for the Briefing screen. Real content (header +
/// three lanes) lands in tasks 4-6 of `BU.13.B`.
class BriefingScreen extends StatelessWidget {
  const BriefingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Briefing')),
      body: const Center(child: Text('Briefing')),
    );
  }
}
