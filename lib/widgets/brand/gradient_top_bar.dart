/// `GradientTopBar` — the 3dp gradient bar every `PanelCard` wears at its
/// top edge (`BU.10.B` task 2, ported from
/// `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: the `GRADIENT_BACKGROUND` map keyed by `GradientHue`, each
/// value a `linear-gradient(to right, ...)` pair, rendered via a `<div>`
/// marked `aria-hidden` and 3px tall. `hueForIndex` cycles the four hues,
/// guarded for negative indices via
/// `((index % length) + length) % length`.
///
/// Every colour comes from [AppTokens] — this file holds no raw colour
/// literals, per the block's acceptance criteria.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The four gradient hues a [GradientTopBar] (or [HeadingRule]) can render,
/// in the web's `GRADIENT_HUES` order.
enum GradientHue { bluePurple, blue, purple, purpleBlue }

/// Resolves [hue] to its `Alignment.centerLeft` → `Alignment.centerRight`
/// [LinearGradient], ported verbatim from the web `GRADIENT_BACKGROUND` map.
LinearGradient gradientForHue(GradientHue hue) {
  final (Color start, Color end) = switch (hue) {
    GradientHue.bluePurple => (AppTokens.primary, AppTokens.accent3),
    GradientHue.blue => (AppTokens.primary, AppTokens.accent2),
    GradientHue.purple => (AppTokens.accent3, AppTokens.primary),
    GradientHue.purpleBlue => (AppTokens.accent3, AppTokens.accent2),
  };
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [start, end],
  );
}

/// Cycles [GradientHue] by [index], matching the web `hueForIndex`.
///
/// Correct for negative indices: Dart's `%` on `int` already returns a
/// non-negative result for a positive modulus (unlike some C-family
/// languages), so this is equivalent to the web's explicit
/// `((index % length) + length) % length` guard without needing to repeat
/// it — verified by test, not assumed.
GradientHue hueForIndex(int index) {
  final values = GradientHue.values;
  final normalized = ((index % values.length) + values.length) % values.length;
  return values[normalized];
}

/// A decorative 3dp-tall gradient bar spanning the full width of its
/// parent, intended to sit at the top of a [PanelCard].
///
/// Marked with [ExcludeSemantics] — the web equivalent sets `aria-hidden`
/// because the bar carries no accessible information.
class GradientTopBar extends StatelessWidget {
  const GradientTopBar({super.key, this.hue = GradientHue.bluePurple});

  /// Which of the four brand gradients to render.
  final GradientHue hue;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        height: 3,
        decoration: BoxDecoration(gradient: gradientForHue(hue)),
      ),
    );
  }
}
