/// `AgeChip` — a small chip rendering "how long ago" a timestamp was, in
/// the largest unit that fits, crossing to the `warning` tone at a
/// staleness threshold (`BU.13.A` task 1).
///
/// The tone change carries the staleness signal, not the text alone
/// (principle 3, `planning/phase-13-operator-instrument.md` §4) — a chip at
/// or past [staleThreshold] renders in [StatusTones.warning]; below it, in
/// [StatusTones.neutral]. Colours are read from the ambient [StatusTones]
/// theme extension via [BuildContext] — this file holds no raw colour
/// literals.
///
/// [age] is a plain [Duration] computed by the caller (or via
/// [AgeChip.since], which computes it from an explicit `now` argument) —
/// this widget never reads the wall clock inside [build], which would make
/// it untestable and non-deterministic.
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// The default staleness threshold: one day.
const Duration kDefaultAgeChipStaleThreshold = Duration(hours: 24);

/// Formats [age] into the largest unit that fits: `just now` (under a
/// minute), `Nm` (minutes, under an hour), `Nh` (hours, under a day), or
/// `Nd` (days, one day and beyond).
///
/// Boundary behaviour is pinned by test: 59s → `just now`, 60s → `1m`,
/// 59m → `59m`, 60m → `1h`, 23h → `23h`, 24h → `1d`.
String formatAgeChipLabel(Duration age) {
  final totalSeconds = age.inSeconds;
  if (totalSeconds < 60) return 'just now';

  final totalMinutes = age.inMinutes;
  if (totalMinutes < 60) return '${totalMinutes}m';

  final totalHours = age.inHours;
  if (totalHours < 24) return '${totalHours}h';

  final totalDays = age.inDays;
  return '${totalDays}d';
}

/// A chip showing an elapsed-time label, changing tone (not just text) at
/// its staleness threshold.
class AgeChip extends StatelessWidget {
  const AgeChip({
    super.key,
    required this.age,
    this.staleThreshold = kDefaultAgeChipStaleThreshold,
  });

  /// Builds an [AgeChip] from an explicit [timestamp] and an injectable
  /// [now], rather than reading the wall clock — keeps the widget
  /// deterministic and testable.
  factory AgeChip.since(
    DateTime timestamp, {
    required DateTime now,
    Duration staleThreshold = kDefaultAgeChipStaleThreshold,
    Key? key,
  }) {
    return AgeChip(
      key: key,
      age: now.difference(timestamp),
      staleThreshold: staleThreshold,
    );
  }

  /// How long ago the event happened.
  final Duration age;

  /// At or past this age, the chip renders in the warning tone.
  final Duration staleThreshold;

  /// Whether [age] is at or past [staleThreshold].
  bool get isStale => age >= staleThreshold;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final tone = isStale ? tones.warning : tones.neutral;
    final label = formatAgeChipLabel(age);

    final style = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 12,
      color: tone.foreground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        border: Border.all(color: tone.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Text(label, style: style),
    );
  }
}
