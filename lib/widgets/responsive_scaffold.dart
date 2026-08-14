/// Phone-vs-tablet responsive split (BU.4.A).
///
/// Below [breakpoint] (logical width) only [list] is shown, topped by an
/// [AppBar] carrying the [BastielLockup]; at/above it a [list] + [detail]
/// split renders side by side, with the same lockup as the rail's header
/// (`ticket-brand-header-lockup` task 2 — the app reads as bastiel on both
/// form factors, not only one). [isWide] exposes the same threshold so
/// callers (e.g. a list screen) can decide push-navigation vs inline
/// selection consistently.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'brand/brand.dart';

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
    // The lockup rides in a real AppBar rather than a plain header row —
    // this is the "app bar" presentation the ticket calls for on phone
    // widths. Icon + wordmark are shown by default (no divergence from the
    // web's `sm`-breakpoint hiding rule needed here: the lockup is ~160dp
    // wide, well under any supported phone width, so it never overflows the
    // AppBar's title slot).
    if (MediaQuery.sizeOf(context).width < breakpoint) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(title: const BastielLockup()),
          Expanded(child: list),
        ],
      );
    }
    // Tablet split: the list rail reads as a nav surface one ground step up
    // from the page (AppTokens.surface), separated from the detail pane by
    // an explicit AppTokens.line hairline — the ground ladder's "prefer a
    // ground step over adding a hairline" rule still leaves this one
    // hairline as the seam between two panes, not a stand-in for a ground
    // step. The lockup sits atop the rail as its header, same treatment as
    // the phone AppBar so the brand reads consistently across both form
    // factors.
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
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: BastielLockup(),
                  ),
                  Expanded(child: list),
                ],
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
