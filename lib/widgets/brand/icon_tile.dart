/// `IconTile` — the 40dp tinted icon square used ahead of headings and list
/// rows (`BU.10.B` task 3, ported from
/// `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: `size-10 rounded-xl border` with a `color-mix(... 14% ...)`
/// fill and a `color-mix(... 30% ...)` border, the icon itself rendered at
/// full colour, marked `aria-hidden` because the adjacent heading carries
/// the accessible name.
///
/// Every colour comes from [AppTokens] (via the existing [AppTokens.alpha]
/// helper) — this file holds no raw colour literals, per the block's
/// acceptance criteria.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The three accent hues an [IconTile] can be tinted with.
enum IconAccent { primary, accent2, accent3 }

/// Resolves [accent] to its [AppTokens] colour.
Color colorForIconAccent(IconAccent accent) {
  return switch (accent) {
    IconAccent.primary => AppTokens.primary,
    IconAccent.accent2 => AppTokens.accent2,
    IconAccent.accent3 => AppTokens.accent3,
  };
}

/// A decorative 40dp tinted square holding a single icon.
///
/// The fill is [accent] at 14% alpha, the 1dp border is [accent] at 30%
/// alpha (the web's `color-mix(... 14%/30% ...)` pair, via the existing
/// [AppTokens.alpha] helper — no new alpha helper is written), and the icon
/// itself renders at the accent's full colour.
///
/// Wrapped in [ExcludeSemantics]: the web marks the equivalent element
/// `aria-hidden` because the adjacent heading carries the accessible name.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.accent = IconAccent.primary,
  });

  /// The icon to render, centred in the tile.
  final IconData icon;

  /// Which of the three accent hues to tint the tile with.
  final IconAccent accent;

  @override
  Widget build(BuildContext context) {
    final color = colorForIconAccent(accent);
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTokens.alpha(color, 0.14),
          border: Border.all(color: AppTokens.alpha(color, 0.30), width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }
}
