/// `SeverityRow` — one ranked list row: a 3dp severity stripe on the
/// leading edge, a title, a trailing `StatusPill`, a meta sub-line, and an
/// optional trailing detail slot (`BU.13.A` task 5, specimen the
/// `cardline` blocks at
/// `planning/artifacts/from-inventory-to-instrument.html:387-421`).
///
/// Severity is carried by the stripe **and** by a non-colour channel (the
/// title's font weight climbs with severity) — principle 3: colour alone
/// fails in sunlight, at a glance, and for a colour-blind operator. A test
/// must be able to pin the severity signal without ever inspecting colour.
///
/// The trailing detail slot exists so `BU.13.C`/`13.D` can pass a
/// `LaneBar`, a `Sparkline`, or nothing at all — this widget takes plain
/// values and widgets, never a DTO.
///
/// Colours come from [StatusTones] via the `BuildContext` accessor; the
/// pill is composed from the existing [StatusPill] (four tones, never a
/// fifth) rather than a new pill being drawn here.
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../brand/status_pill.dart';

/// The four severities a [SeverityRow] can render, matching the specimen's
/// `s-crit` / `s-warn` / `s-ok` / `s-idle` stripe classes.
enum SeverityRowSeverity { idle, ok, warn, crit }

extension on SeverityRowSeverity {
  /// Resolves this severity's [StatusTone] — the stripe/colour channel.
  ///
  /// Exhaustive `switch` expression with no `default` arm, matching the
  /// discipline `StatusPillTone`/`StatTileSeverity`/`LaneBarSegment`
  /// already use: a fifth severity is a compile error, not a silent
  /// fallback.
  StatusTone toneOf(StatusTones tones) => switch (this) {
    SeverityRowSeverity.crit => tones.danger,
    SeverityRowSeverity.warn => tones.warning,
    SeverityRowSeverity.ok => tones.success,
    SeverityRowSeverity.idle => tones.neutral,
  };

  /// The non-colour severity channel: the title's font weight climbs with
  /// severity, so the signal survives a screenshot in grayscale. Pinned by
  /// a test that never inspects colour.
  FontWeight get titleWeight => switch (this) {
    SeverityRowSeverity.crit => FontWeight.w800,
    SeverityRowSeverity.warn => FontWeight.w700,
    SeverityRowSeverity.ok => FontWeight.w600,
    SeverityRowSeverity.idle => FontWeight.w500,
  };
}

/// One ranked list row: severity stripe, title, trailing [StatusPill],
/// meta sub-line, and an optional trailing detail widget.
class SeverityRow extends StatelessWidget {
  const SeverityRow({
    super.key,
    required this.severity,
    required this.title,
    required this.pillTone,
    required this.pillLabel,
    required this.meta,
    this.trailingDetail,
    this.stripeWidth = 3,
  });

  /// Which severity this row renders — drives both the stripe tone and the
  /// non-colour title-weight channel.
  final SeverityRowSeverity severity;

  /// The row's title (e.g. a repo name).
  final String title;

  /// Which of the four fixed [StatusPill] tones the trailing pill renders
  /// in. [SeverityRow] never draws its own pill.
  final StatusPillTone pillTone;

  /// The trailing pill's label (e.g. `"2 GATES"`, `"STALE 9d"`).
  final String pillLabel;

  /// The meta sub-line beneath the title (e.g.
  /// `"14 blocks · 6 blocked · touched 4m ago"`). Any comparable number in
  /// it renders with tabular figures, so a column of these rows lines up.
  final String meta;

  /// An optional widget rendered beneath the meta line — a caller-supplied
  /// `LaneBar`, `Sparkline`, or `null` for a row with no further detail
  /// (`BU.13.C`/`13.D` decide, not this widget).
  final Widget? trailingDetail;

  /// The stripe's width in logical pixels. Defaults to the specimen's 3dp.
  final double stripeWidth;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final tone = severity.toneOf(tones);

    final titleStyle = TextStyle(
      fontFamily: AppTypography.textTheme.titleSmall?.fontFamily,
      fontWeight: severity.titleWeight,
      fontSize: AppTypography.textTheme.titleSmall?.fontSize ?? 14,
      color: AppTokens.ink,
    );

    final metaStyle = TextStyle(
      fontFamily: AppTypography.textTheme.bodySmall?.fontFamily,
      fontWeight: FontWeight.w400,
      fontSize: AppTypography.textTheme.bodySmall?.fontSize ?? 11,
      color: tones.neutral.foreground,
      height: 1.45,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            key: const ValueKey('severity-row-stripe'),
            left: 0,
            top: 0,
            bottom: 0,
            width: stripeWidth,
            child: ColoredBox(color: tone.foreground),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: stripeWidth + 10,
              right: 13,
              top: 11,
              bottom: 11,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        key: const ValueKey('severity-row-title'),
                        style: titleStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(tone: pillTone, label: pillLabel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  key: const ValueKey('severity-row-meta'),
                  style: metaStyle,
                ),
                if (trailingDetail != null) ...[
                  const SizedBox(height: 8),
                  trailingDetail!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
