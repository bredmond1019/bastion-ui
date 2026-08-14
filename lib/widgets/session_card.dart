/// A single session summary card for the sessions-list screen.
///
/// Renders a running/idle badge (from [SessionDto.state]), the session name,
/// its last foreground line, an agent-activity chip (from
/// [SessionDto.agentState] — distinct from the running/idle badge, see
/// [_AgentStateChip]), and — when [needsInput] is true — a needs-input flag
/// badge driven by `events_provider.dart`.
///
/// Purely presentational: does not read providers itself, so it stays easy
/// to unit-test with plain constructor arguments.
library;

import 'package:flutter/material.dart';

import '../models/session_dto.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(session.name)),
            if (session.agentState != AgentState.unknown) ...[
              const SizedBox(width: 8),
              _AgentStateChip(agentState: session.agentState),
            ],
          ],
        ),
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
    final tones = context.statusTones;
    return Tooltip(
      message: isRunning ? 'Running' : 'Idle',
      child: CircleAvatar(
        radius: 6,
        backgroundColor: isRunning
            ? tones.active.foreground
            : tones.neutral.foreground,
      ),
    );
  }
}

/// Labelled chip surfacing [SessionDto.agentState] — detected AGENT
/// activity, as opposed to [_StateBadge]'s tmux PANE liveness. The two are
/// independent (a session can be `state: running` with `agent_state:
/// idle`), so this is a distinct affordance rather than a replacement for
/// the leading dot. [AgentState.unknown] renders no chip at all (handled by
/// the caller) — an unknown state is noise, not signal.
///
/// `blocked` carries the most visual weight (bold text, filled background):
/// it is the state the operator most needs to act on.
class _AgentStateChip extends StatelessWidget {
  const _AgentStateChip({required this.agentState});

  final AgentState agentState;

  String get _label {
    switch (agentState) {
      case AgentState.working:
        return 'working';
      case AgentState.idle:
        return 'idle';
      case AgentState.blocked:
        return 'blocked';
      case AgentState.unknown:
        return 'unknown';
    }
  }

  StatusTone _tone(StatusTones tones) {
    switch (agentState) {
      case AgentState.working:
        return tones.info;
      case AgentState.idle:
        return tones.neutral;
      case AgentState.blocked:
        return tones.danger;
      case AgentState.unknown:
        return tones.neutral;
    }
  }

  bool get _emphasized => agentState == AgentState.blocked;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context.statusTones);
    final color = tone.foreground;
    return Tooltip(
      message: 'Agent $_label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _emphasized ? color : tone.background,
          borderRadius: BorderRadius.circular(4),
          border: _emphasized ? null : Border.all(color: tone.border, width: 1),
        ),
        child: Text(
          _label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: _emphasized ? FontWeight.bold : FontWeight.w500,
            color: _emphasized ? AppTokens.paper : color,
          ),
        ),
      ),
    );
  }
}

/// Flag badge shown on a card whose session is waiting on operator input.
class _NeedsInputBadge extends StatelessWidget {
  const _NeedsInputBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Needs input',
      child: Icon(
        Icons.notifications_active,
        color: context.statusTones.warning.foreground,
      ),
    );
  }
}
