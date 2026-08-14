/// `PanelCard` — the card ground every brand panel/disclosure sits on
/// (`BU.10.B` task 1, ported from `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: `rounded-2xl border border-line bg-surface overflow-hidden`,
/// `relative` (so a child `GradientTopBar` positions against the card, not
/// the page), plus `focus-within:ring-2 focus-within:ring-accent-2/50`.
///
/// Every colour comes from [AppTokens] — this file holds no raw colour
/// literals, per the block's acceptance criteria.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The card ground every disclosure panel renders on.
///
/// Renders [child] as the first (and only) slot of an internal [Stack], so
/// a caller-composed `GradientTopBar` (or any other absolutely-positioned
/// overlay) can be layered as a sibling inside that `Stack` and still be
/// clipped to the card's rounded corners.
///
/// Shows a 2dp focus ring — [AppTokens.accent2] at 50% alpha — whenever
/// this card or any descendant inside [child] holds focus (the web
/// `focus-within` pseudo-class), reproduced as a [BoxShadow] rather than an
/// extra border so it does not perturb layout.
class PanelCard extends StatefulWidget {
  const PanelCard({super.key, required this.child});

  /// The panel's content. Rendered inside a [Stack] so sibling overlays
  /// (e.g. a [GradientTopBar]) can be composed by the caller.
  final Widget child;

  @override
  State<PanelCard> createState() => _PanelCardState();
}

class _PanelCardState extends State<PanelCard> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PanelCard');
  bool _focusWithin = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus != _focusWithin) {
      setState(() => _focusWithin = hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `FocusNode.hasFocus` (surfaced here via `onFocusChange`) is true when
    // this node OR a descendant holds primary focus — the Flutter analogue
    // of CSS `focus-within` — so no manual descendant tracking is needed.
    return Focus(
      focusNode: _focusNode,
      onFocusChange: _handleFocusChange,
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: AppTokens.line, width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusXxl),
          boxShadow: _focusWithin
              ? [
                  BoxShadow(
                    color: AppTokens.alpha(AppTokens.accent2, 0.5),
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [widget.child]),
      ),
    );
  }
}
