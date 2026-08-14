/// `GateCard` — the operator-gate card: a gate's name, what it is waiting
/// on, and its downstream blast radius (how many blocks it gates), carrying
/// one primary action affordance (`BU.13.A` task 6, specimen §04 The
/// Briefing, where the gate card is the screen's one primary action —
/// principle 5).
///
/// A gate blocking six blocks must read as more urgent than one blocking
/// one, so the blast radius is a comparable number and always rendered
/// with [FontFeature.tabularFigures()].
///
/// The primary action is taken as a plain callback ([onAct]) — this widget
/// does not wire it to anything; no screen consumes `GateCard` when this
/// block lands (`BU.13.B`–`13.E` do that). Composes [PanelCard] for the
/// ground rather than drawing a new card surface, and reads every colour
/// from [StatusTones]/[AppTokens] via the `BuildContext` accessor — this
/// file holds no raw colour literals.
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../brand/panel_card.dart';

/// A single operator gate: name, what it is waiting on, downstream blast
/// radius, and one primary action.
class GateCard extends StatelessWidget {
  const GateCard({
    super.key,
    required this.name,
    required this.waitingOn,
    required this.blastRadius,
    required this.onAct,
    this.actionLabel = 'Act',
  });

  /// The gate's name (e.g. `"Ship the operator instrument"`).
  final String name;

  /// What the gate is waiting on (e.g. `"your review"`, `"CI"`).
  final String waitingOn;

  /// How many blocks this gate gates — its downstream blast radius. `0` or
  /// a negative/unknown value degrades gracefully to an em dash rather
  /// than a misleading `"0"`.
  final int? blastRadius;

  /// Fired when the operator taps the primary action. Not wired to
  /// anything by this widget — the caller owns what "act" means.
  final VoidCallback onAct;

  /// The primary action button's label. Defaults to `"Act"`.
  final String actionLabel;

  /// Formats [blastRadius] for display: a tabular-figure count, or an em
  /// dash when the value is `null`, zero, or negative (unknown/none).
  static String _formatBlastRadius(int? blastRadius) {
    if (blastRadius == null || blastRadius <= 0) return '—';
    return '$blastRadius';
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final radiusText = _formatBlastRadius(blastRadius);
    final hasBlastRadius = blastRadius != null && blastRadius! > 0;
    final radiusTone = hasBlastRadius ? tones.warning : tones.neutral;

    final nameStyle = TextStyle(
      fontFamily: AppTypography.textTheme.titleMedium?.fontFamily,
      fontWeight: FontWeight.w700,
      fontSize: AppTypography.textTheme.titleMedium?.fontSize ?? 16,
      color: AppTokens.ink,
    );

    final waitingOnStyle = TextStyle(
      fontFamily: AppTypography.textTheme.bodyMedium?.fontFamily,
      fontWeight: FontWeight.w400,
      fontSize: AppTypography.textTheme.bodyMedium?.fontSize ?? 13,
      color: tones.neutral.foreground,
    );

    final radiusNumberStyle = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: FontWeight.w700,
      fontSize: AppTypography.textTheme.headlineSmall?.fontSize ?? 24,
      color: radiusTone.foreground,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final radiusLabelStyle = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 11,
      color: tones.neutral.foreground,
      letterSpacing: 0.8,
    );

    return PanelCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, key: const ValueKey('gate-card-name'), style: nameStyle),
            const SizedBox(height: 4),
            Text(
              waitingOn,
              key: const ValueKey('gate-card-waiting-on'),
              style: waitingOnStyle,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      radiusText,
                      key: const ValueKey('gate-card-blast-radius'),
                      style: radiusNumberStyle,
                    ),
                    const SizedBox(height: 4),
                    Text('BLOCKS GATED', style: radiusLabelStyle),
                  ],
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('gate-card-action'),
                  onPressed: onAct,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
