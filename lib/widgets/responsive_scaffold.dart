/// Phone-vs-tablet responsive split (BU.4.A).
///
/// Below [breakpoint] (logical width) only [list] is shown; at/above it a
/// [list] + [detail] split renders side by side. [isWide] exposes the same
/// threshold so callers (e.g. a list screen) can decide push-navigation vs
/// inline selection consistently.
library;

import 'package:flutter/material.dart';

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.list,
    required this.detail,
    this.breakpoint = kTabletBreakpoint,
  });

  /// Default tablet breakpoint in logical pixels.
  static const double kTabletBreakpoint = 720.0;

  final Widget list;
  final Widget detail;
  final double breakpoint;

  /// True when the current media width is at/above the tablet breakpoint.
  static bool isWide(
    BuildContext context, {
    double breakpoint = kTabletBreakpoint,
  }) => MediaQuery.sizeOf(context).width >= breakpoint;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < breakpoint) {
      return list;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: list),
        const VerticalDivider(width: 1),
        Expanded(flex: 5, child: detail),
      ],
    );
  }
}
