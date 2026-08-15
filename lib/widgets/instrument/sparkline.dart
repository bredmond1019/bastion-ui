/// `Sparkline` — a seven-point activity bar chart with no axes, no labels,
/// no legend (`BU.13.A` task 4, specimen
/// `planning/artifacts/from-inventory-to-instrument.html:400`).
///
/// It is a shape, not a chart: each bar's height is proportional to the
/// max value in the series, and every bar renders in a single tone — never
/// coloured individually, so no one point reads as more or less important
/// than any other. Callers pass raw values; this widget never reads a
/// clock or a DTO.
///
/// Degenerate series must render without throwing: fewer than seven
/// points, all values equal (a flat, uniform row — not a division-by-
/// zero), and all zeroes (a flat, minimum-height row).
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';

/// A seven-point (or fewer) activity bar chart. Heights are proportional
/// to the max value in [values]; there are no axes, labels, or legend.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 22});

  /// The series to plot, oldest first. Any non-negative length is
  /// accepted — the specimen shows seven points, but fewer must still
  /// render without throwing (`BU.13.C`/`13.D` may have less history for
  /// a young repo).
  final List<double> values;

  /// Overall track height in logical pixels. Defaults to the specimen's
  /// 22px.
  final double height;

  /// The floor every bar renders at, as a fraction of [height]. Keeps a
  /// zero-value point visible as a sliver rather than vanishing — a
  /// sparkline that can disappear mid-row reads as broken, not "zero".
  static const double _minFraction = 0.08;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final color = tones.active.foreground;

    final max = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);

    final bars = <Widget>[
      for (var i = 0; i < values.length; i++)
        Expanded(
          key: ValueKey('sparkline-bar-$i'),
          child: FractionallySizedBox(
            heightFactor: _fractionFor(values[i], max),
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: values.length > 1 ? 1 : 0,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm / 4),
              ),
            ),
          ),
        ),
    ];

    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: bars),
    );
  }

  /// The height fraction (0.0–1.0) a bar for [value] should render at,
  /// given the series [max]. Never divides by zero: an all-zero (or
  /// empty) series maps every bar to [_minFraction], not `NaN`.
  double _fractionFor(double value, double max) {
    if (max <= 0) return _minFraction;
    final fraction = value / max;
    if (fraction.isNaN || fraction <= 0) return _minFraction;
    return fraction.clamp(_minFraction, 1.0);
  }
}
