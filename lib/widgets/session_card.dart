/// A single session summary card for the sessions-list screen.
///
/// Renders a running/idle badge (from [SessionDto.state]), the session name,
/// its last foreground line, and — when [needsInput] is true — a
/// needs-input flag badge driven by `events_provider.dart`.
///
/// Purely presentational: does not read providers itself, so it stays easy
/// to unit-test with plain constructor arguments.
library;

import 'package:flutter/material.dart';

import '../models/session_dto.dart';

/// A running/idle summary card for one [SessionDto].
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    this.needsInput = false,
    this.onTap,
  });

  /// The session this card summarizes.
  final SessionDto session;

  /// Whether a `needs_input` event is currently pending for this session
  /// (per `events_provider.dart`'s `needsInputProvider`).
  final bool needsInput;

  /// Called when the card is tapped — the sessions-list screen wires this
  /// to navigate to the session-detail screen (`BU.1.A` Task 6).
  final VoidCallback? onTap;

  bool get _isRunning => session.state.toLowerCase() == 'running';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: _StateBadge(isRunning: _isRunning),
        title: Text(session.name),
        subtitle: Text(
          session.lastLine?.isNotEmpty == true ? session.lastLine! : ' ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: needsInput ? const _NeedsInputBadge() : null,
      ),
    );
  }
}

/// Small colour-coded dot indicating the session's running/idle state.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.isRunning});

  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isRunning ? 'Running' : 'Idle',
      child: CircleAvatar(
        radius: 6,
        backgroundColor: isRunning
            ? const Color(0xFF388E3C) // green 700
            : const Color(0xFF9E9E9E), // grey 500
      ),
    );
  }
}

/// Flag badge shown on a card whose session is waiting on operator input.
class _NeedsInputBadge extends StatelessWidget {
  const _NeedsInputBadge();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Needs input',
      child: Icon(Icons.notifications_active, color: Color(0xFFE65100)),
    );
  }
}
