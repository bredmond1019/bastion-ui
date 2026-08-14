/// `LaneBar` — a single proportional bar showing a repo's blocks split
/// across four lanes, in the fixed order done · now · blocked · next, with
/// a key row beneath naming each segment (`BU.13.A` task 3, specimen
/// `planning/artifacts/from-inventory-to-instrument.html:388-395`).
///
/// The order is part of the contract, not a display choice — it is what
/// makes two repos' bars comparable at a glance. Callers pass raw counts;
/// this widget computes proportions internally so the caller never has to
/// reconcile rounding.
///
/// Segment colours map to existing [StatusTones] (never a new token):
/// done → `success`, now → `active`, blocked → `danger`, next → `neutral`.
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// The four fixed lanes a [LaneBar] segments its track into, in display
/// order. Order is the contract — never reorder these.
enum LaneBarSegment { done, now, blocked, next }

/// A single lane's raw count and display label.
@immutable
class LaneBarLane {
  const LaneBarLane({required this.segment, required this.count});

  final LaneBarSegment segment;
  final int count;
}

extension on LaneBarSegment {
  String get label => switch (this) {
    LaneBarSegment.done => 'done',
    LaneBarSegment.now => 'now',
    LaneBarSegment.blocked => 'blocked',
    LaneBarSegment.next => 'next',
  };

  /// Resolves this segment's fixed [StatusTone] mapping. Exhaustive switch
  /// with no `default` — a fifth lane is a compile error, matching the
  /// discipline `StatusPillTone`/`StatTileSeverity` already use.
  StatusTone toneOf(StatusTones tones) => switch (this) {
    LaneBarSegment.done => tones.success,
    LaneBarSegment.now => tones.active,
    LaneBarSegment.blocked => tones.danger,
    LaneBarSegment.next => tones.neutral,
  };
}

/// One horizontal bar, four proportional segments in the fixed order
/// done · now · blocked · next, with a key row naming each segment.
class LaneBar extends StatelessWidget {
  const LaneBar({
    super.key,
    required this.done,
    required this.now,
    required this.blocked,
    required this.next,
    this.height = 5,
  });

  /// Count of blocks already done.
  final int done;

  /// Count of blocks currently in flight.
  final int now;

  /// Count of blocked blocks.
  final int blocked;

  /// Count of blocks not yet started.
  final int next;

  /// Track height in logical pixels. Defaults to the specimen's ~5dp.
  final double height;

  /// The four counts in fixed display order, as [LaneBarSegment] values.
  List<LaneBarLane> get lanes => [
    LaneBarLane(segment: LaneBarSegment.done, count: done),
    LaneBarLane(segment: LaneBarSegment.now, count: now),
    LaneBarLane(segment: LaneBarSegment.blocked, count: blocked),
    LaneBarLane(segment: LaneBarSegment.next, count: next),
  ];

  /// Total count across all four lanes.
  int get total => done + now + blocked + next;

  /// Computes each lane's integer flex weight such that the four weights
  /// always sum to exactly [precision] — never a pixel short or a pixel
  /// over from naive independent rounding.
  ///
  /// Uses the largest-remainder method: floor each lane's exact share,
  /// then hand out the leftover units to the lanes with the largest
  /// fractional remainders. All-zero input maps every weight to zero
  /// except a single neutral filler, so the track still renders as a
  /// full (empty) bar instead of collapsing to nothing.
  List<int> _weights({int precision = 1000}) {
    final counts = lanes.map((l) => l.count).toList();
    final sum = total;
    if (sum <= 0) {
      // Degenerate: nothing to show. Render a single neutral filler so
      // the track still occupies its full width.
      return [0, 0, 0, precision];
    }

    final exact = counts.map((c) => c * precision / sum).toList();
    final floors = exact.map((e) => e.floor()).toList();
    var remainder = precision - floors.reduce((a, b) => a + b);

    // Distribute the leftover `remainder` units to the lanes with the
    // largest fractional part first.
    final order = List<int>.generate(counts.length, (i) => i)
      ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));

    final weights = List<int>.from(floors);
    for (final i in order) {
      if (remainder <= 0) break;
      weights[i] += 1;
      remainder -= 1;
    }
    return weights;
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final weights = _weights();
    final isEmpty = total <= 0;

    // Use each segment's foreground tone for the bar fill — the
    // background triplet is too faint (an alpha tint) to read as a
    // filled bar on its own.
    final fillSegments = <Widget>[];
    for (var i = 0; i < lanes.length; i++) {
      final weight = weights[i];
      if (weight <= 0) continue;
      final tone = isEmpty ? tones.neutral : lanes[i].segment.toneOf(tones);
      fillSegments.add(
        Expanded(
          key: ValueKey('lanebar-segment-${lanes[i].segment.name}'),
          flex: weight,
          child: Container(color: tone.foreground),
        ),
      );
    }

    final keyStyle = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 10,
      color: tones.neutral.foreground,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: SizedBox(
            height: height,
            child: Row(children: fillSegments),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final lane in lanes)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: lane.segment.toneOf(tones).foreground,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(lane.segment.label, style: keyStyle),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
