/// Small colour-coded status badge for a dashboard repo row.
///
/// Reflects three mutually-exclusive states, in priority order — an
/// in-flight SDLC workflow running for the repo outranks a pending
/// `handoff.md` awaiting review, which outranks neither (idle). Purely
/// presentational: the caller (`dashboard_screen.dart`) derives the
/// [RepoBadgeState] from provider state, so this widget stays easy to
/// unit-test with plain constructor arguments.
library;

import 'package:flutter/material.dart';

/// The dashboard repo-row status a [StatusBadge] represents.
enum RepoBadgeState {
  /// No in-flight workflow and no pending handoff.
  idle,

  /// An SDLC workflow is currently running for this repo.
  inFlight,

  /// A `handoff.md` is present for this repo (and no workflow is running).
  hasHandoff,
}

/// Colour + icon + tooltip badge for a [RepoBadgeState].
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.state});

  /// The state this badge renders.
  final RepoBadgeState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case RepoBadgeState.inFlight:
        return const Tooltip(
          message: 'Workflow in flight',
          child: Icon(Icons.autorenew, color: Color(0xFF1976D2)), // blue 700
        );
      case RepoBadgeState.hasHandoff:
        return const Tooltip(
          message: 'Handoff pending',
          child: Icon(
            Icons.assignment_late,
            color: Color(0xFFE65100), // orange 900
          ),
        );
      case RepoBadgeState.idle:
        return const Tooltip(
          message: 'Idle',
          child: CircleAvatar(
            radius: 6,
            backgroundColor: Color(0xFF9E9E9E), // grey 500
          ),
        );
    }
  }
}
