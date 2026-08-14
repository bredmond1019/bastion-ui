/// `HeadingRule` — the 3dp x 56dp gradient underline every brand heading
/// wears (`BU.10.B` task 5, ported from
/// `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: `h-[3px] w-14` (Tailwind `w-14` = 3.5rem = 56px), a fully
/// rounded bar filled with the primary -> accent3 gradient, marked
/// `aria-hidden`.
///
/// Reuses [gradientForHue] with [GradientHue.bluePurple] from
/// `gradient_top_bar.dart` rather than redeclaring the primary -> accent3
/// colour pair, so the two cannot drift.
///
/// Every colour comes from [AppTokens] (via [gradientForHue]) — this file
/// holds no raw colour literals, per the block's acceptance criteria.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'gradient_top_bar.dart';

/// A decorative 3dp-tall, 56dp-wide, fully-rounded gradient underline,
/// intended to sit under a brand heading.
///
/// Marked with [ExcludeSemantics] — the web equivalent sets `aria-hidden`
/// because the bar carries no accessible information.
class HeadingRule extends StatelessWidget {
  const HeadingRule({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 3,
        decoration: BoxDecoration(
          gradient: gradientForHue(GradientHue.bluePurple),
          borderRadius: BorderRadius.circular(AppTokens.radiusXxxxl),
        ),
      ),
    );
  }
}
