/// Runs screen — live workflow runs, pushed over the `runs` WS topic.
///
/// `BU.13.E` task 3 wires this screen into `HomeShell` as its own tab first
/// (this repo has shipped unreachable UI twice with a fully green suite —
/// see `main.dart`'s `_ConnectedBody` doc comment) so every later task in
/// this block lands on a screen already reachable from the real route
/// rather than a synthetic pump. This is a minimal scaffold: the REST seed
/// + live `runs` topic subscription (task 4) and the vertical run/node list
/// with suspended/empty states (task 5) land in later tasks.
library;

import 'package:flutter/material.dart';

/// Placeholder body for the runs tab — real content lands in `BU.13.E`
/// tasks 4-6 (`runs_provider.dart` seed + live subscription, then the
/// vertical run/node list with suspended and no-engine empty states).
class RunsScreen extends StatelessWidget {
  const RunsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Runs')),
      body: const Center(child: Text('Runs')),
    );
  }
}
