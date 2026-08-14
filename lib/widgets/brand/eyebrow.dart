/// `Eyebrow` — the mono uppercase kicker with a glowing dot, used ahead of
/// section headings (`BU.10.B` task 4, ported from
/// `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: a 7px circular dot in `--accent-2` carrying a glow
/// (`shadow-[0_0_12px_1px_var(--accent-2)]`), a small gap, then a mono
/// uppercase label at `tracking-[0.16em]`.
///
/// Every colour comes from [AppTokens] — this file holds no raw colour
/// literals, per the block's acceptance criteria.
///
/// Brand label rule: [Eyebrow] is one of only two primitives in this block
/// permitted the mono+uppercase pair (the other is `StatusPill`), and it
/// carries that treatment exactly once here.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// A small mono, uppercase kicker label with a glowing accent dot,
/// typically placed above a heading.
///
/// [label] is uppercased by the widget itself — callers should not
/// pre-uppercase it.
class Eyebrow extends StatelessWidget {
  const Eyebrow({super.key, required this.label});

  /// The kicker text. Rendered uppercased regardless of input casing.
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTypography.labelMedium.fontFamily,
      fontWeight: AppTypography.labelMedium.fontWeight,
      fontSize: AppTypography.labelMedium.fontSize,
      color: AppTokens.accent2,
      letterSpacing: 0.16 * AppTypography.labelMedium.fontSize!,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTokens.accent2,
            boxShadow: [
              BoxShadow(
                color: AppTokens.accent2,
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(label.toUpperCase(), style: style),
      ],
    );
  }
}
