/// A single session summary card for the sessions-list screen.
///
/// Renders a running/idle badge (from [SessionDto.state]), the session name,
/// its last foreground line, an agent-activity chip (from
/// [SessionDto.agentState] — distinct from the running/idle badge, see
/// [_AgentStateChip]), and — when [needsInput] is true — a needs-input flag
/// badge driven by `events_provider.dart`.
///
/// Re-skinned in `BU.10.C` task 2: the card is now a [PanelCard] wearing a
/// [GradientTopBar] whose hue cycles by [index] (`hueForIndex`) so adjacent
/// cards in the list don't read identically — one gradient bar per panel,
/// per the block's budget rule. The agent-state chip now renders through
/// [StatusPill] rather than a bespoke container.
///
/// Purely presentational: does not read providers itself, so it stays easy
/// to unit-test with plain constructor arguments.
library;

import 'package:flutter/material.dart';

import '../models/session_dto.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'brand/brand.dart';

/// A running/idle summary card for one [SessionDto].
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    this.index = 0,
    this.needsInput = false,
    this.onTap,
  });

  /// The session this card summarizes.
  final SessionDto session;

  /// This card's position in the (sorted) sessions list, used to cycle the
  /// [GradientTopBar]'s hue via `hueForIndex` so adjacent cards don't read
  /// identically. Defaults to 0 (the first hue) for direct/unit-test
  /// construction outside a list.
  final int index;

  /// Whether a `needs_input` event is currently pending for this session
  /// (per `events_provider.dart`'s `needsInputProvider`).
  final bool needsInput;

  /// Called when the card is tapped — the sessions-list screen wires this
  /// to navigate to the session-detail screen (`BU.1.A` Task 6).
  final VoidCallback? onTap;

  bool get _isRunning => session.state.toLowerCase() == 'running';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: PanelCard(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Budget rule: one gradient bar per panel — this is it, no
              // inner region gets a second one.
              GradientTopBar(hue: hueForIndex(index)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StateBadge(isRunning: _isRunning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  session.name,
                                  style: AppTypography.textTheme.titleSmall
                                      ?.copyWith(color: AppTokens.ink),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (session.agentState != AgentState.unknown) ...[
                                const SizedBox(width: 8),
                                _AgentStateChip(agentState: session.agentState),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            session.lastLine?.isNotEmpty == true
                                ? session.lastLine!
                                : ' ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.mono.copyWith(
                              color: AppTokens.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (needsInput) ...[
                      const SizedBox(width: 8),
                      const _NeedsInputBadge(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
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
/// Renders through [StatusPill] (`BU.10.C` task 2), mapped onto the
/// closest-fitting [StatusPillTone]: `blocked` maps 1:1 (the state the
/// operator most needs to act on), `working` maps onto `inProgress`, and
/// `idle` maps onto `onTrack` (nothing needs the operator).
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

  StatusPillTone get _tone {
    switch (agentState) {
      case AgentState.working:
        return StatusPillTone.inProgress;
      case AgentState.idle:
        return StatusPillTone.onTrack;
      case AgentState.blocked:
        return StatusPillTone.blocked;
      case AgentState.unknown:
        return StatusPillTone.inProgress;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Agent $_label',
      child: StatusPill(tone: _tone, label: _label),
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
