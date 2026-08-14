/// `StatTile` — a big tabular number over a mono label, the leading
/// primitive of the Briefing screen's "three numbers before anything else"
/// treatment (`BU.13.A` task 2, specimen
/// `planning/artifacts/from-inventory-to-instrument.html:311-315`).
///
/// The number is the thing being compared — a row of `StatTile`s only
/// reads at a glance if the digits line up, so [value] is always rendered
/// with [FontFeature.tabularFigures()]. [severity] optionally shifts the
/// number's tone (e.g. a "need you" count reads in the danger tone, a
/// "blocked" count in the warning tone); the label stays neutral, matching
/// the specimen where only `.n` carries a severity class, never `.l`.
///
/// Colours come from [StatusTones] via the `BuildContext` accessor — this
/// file holds no raw colour literals. Takes a plain value + label, no DTO
/// coupling (`BU.13.C`/`13.D` map their own data onto this).
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// The tone a [StatTile]'s number renders in. `neutral` is the default —
/// most stats (e.g. "running") carry no urgency of their own. `warning`
/// and `danger` mirror the specimen's `.n.warn` / `.n.crit` classes.
enum StatTileSeverity { neutral, warning, danger }

/// A single stat: a large tabular number and a mono, uppercased label
/// beneath it, in an optional severity tone.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.severity = StatTileSeverity.neutral,
  });

  /// The number to display. A plain [String] so callers can pass any
  /// already-formatted value (`"3"`, `"12"`, `"—"`) without this widget
  /// making formatting decisions.
  final String value;

  /// The label beneath the number (e.g. `"need you"`, `"blocked"`,
  /// `"running"`). Rendered uppercased, matching the specimen's `.l` class
  /// and the brand label rule (mono, uppercase, positive tracking —
  /// labels only, never prose).
  final String label;

  /// Which tone the number renders in. The label itself is always the
  /// neutral/faint ink tone, matching the specimen.
  final StatTileSeverity severity;

  /// Resolves [severity] to the [StatusTone] its number should render in.
  ///
  /// Exhaustive `switch` expression with no `default` arm — adding a
  /// fourth [StatTileSeverity] value without handling it here is a compile
  /// error, not a silent runtime fallback (mirrors `statusToneFor`'s
  /// discipline for `StatusPillTone`).
  static StatusTone toneFor(StatTileSeverity severity, StatusTones tones) {
    return switch (severity) {
      StatTileSeverity.neutral => tones.neutral,
      StatTileSeverity.warning => tones.warning,
      StatTileSeverity.danger => tones.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final numberTone = toneFor(severity, tones);
    final labelTone = tones.neutral;

    final numberStyle = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: FontWeight.w700,
      fontSize: AppTypography.textTheme.headlineSmall?.fontSize ?? 24,
      color: numberTone.foreground,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final labelStyle = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 11,
      color: labelTone.foreground,
      letterSpacing: 0.8,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: numberStyle),
          const SizedBox(height: 6),
          Text(label.toUpperCase(), style: labelStyle),
        ],
      ),
    );
  }
}
