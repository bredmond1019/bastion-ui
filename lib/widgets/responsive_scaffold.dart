/// Phone-vs-tablet responsive split (BU.4.A).
///
/// Below [breakpoint] (logical width) only [list] is shown; at/above it a
/// [list] + [detail] split renders side by side. [isWide] exposes the same
/// threshold so callers (e.g. a list screen) can decide push-navigation vs
/// inline selection consistently.
///
/// This widget deliberately carries **no app bar and no brand lockup**. It is
/// used as a `body:` (see `sessions_list_screen.dart`), so anything app-bar
/// shaped here renders *below* `HomeShell`'s real AppBar and only on the one
/// tab that uses it. The lockup therefore lives in `main.dart`'s `HomeShell`
/// AppBar, which is the single bar visible on every tab at every width.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
    // Phone width: the page ground (AppTokens.paper, set globally via
    // AppTheme.dark.scaffoldBackgroundColor) already sits behind `list` via
    // the caller's Scaffold, so there is nothing further to ground here.
    if (MediaQuery.sizeOf(context).width < breakpoint) {
      return list;
    }
    // Tablet split: the list rail reads as a nav surface one ground step up
    // from the page (AppTokens.surface), separated from the detail pane by
    // an explicit AppTokens.line hairline — the ground ladder's "prefer a
    // ground step over adding a hairline" rule still leaves this one
    // hairline as the seam between two panes, not a stand-in for a ground
    // step.
    return Container(
      color: AppTokens.paper,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: ColoredBox(
              color: AppTokens.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: list)],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: AppTokens.line),
          Expanded(flex: 5, child: detail),
        ],
      ),
    );
  }
}
