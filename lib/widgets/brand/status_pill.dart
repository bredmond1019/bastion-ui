/// `StatusPill` — the four-tone status chip, on the calm gear
/// (`BU.10.B` task 6, ported from
/// `../bastion-web/components/ui/brand.tsx`).
///
/// Web source: `StatusPill` composes `statusBadgeVariants({ size: "dense" })`
/// — the web's dense desk-and-mouse type/radius/row metrics. Those metrics
/// are **deliberately not ported** (context.md §3.5 forbids the density
/// gear on a phone screen); only the tone mapping is ported verbatim. This
/// widget uses the calm gear instead: a normal label size from
/// [AppTypography], a token radius from [AppTokens], and comfortable touch
/// padding.
///
/// Every colour comes from the [StatusTones] theme extension (resolved via
/// `Theme.of(context)`, never [StatusTones.dark] directly) — this file
/// holds no raw colour literals, per the block's acceptance criteria.
///
/// Brand label rule: [StatusPill] is the second and last primitive in this
/// block permitted the mono+uppercase pair (the other is `Eyebrow`), and it
/// carries that treatment exactly once here.
library;

import 'package:flutter/material.dart';

import '../../theme/status_tones.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// The four status tones a [StatusPill] can render, matching the web
/// `StatusPillTone` union exactly.
enum StatusPillTone { onTrack, needsYou, blocked, inProgress }

/// Resolves [tone] to its [StatusTone] within [tones].
///
/// The `switch` is exhaustive with no `default` branch: adding a fifth
/// [StatusPillTone] value without handling it here is a compile error, not
/// a silent runtime fallback.
StatusTone statusToneFor(StatusPillTone tone, StatusTones tones) {
  return switch (tone) {
    StatusPillTone.onTrack => tones.active,
    StatusPillTone.needsYou => tones.success,
    StatusPillTone.blocked => tones.danger,
    StatusPillTone.inProgress => tones.neutral,
  };
}

/// A small pill showing a dot + uppercased mono label in one of four
/// semantic tones, resolved from the ambient [StatusTones] theme extension.
///
/// Deliberately built on the calm gear, not the web's dense metrics — see
/// this file's doc comment.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.tone, required this.label});

  /// Which of the four tones to render.
  final StatusPillTone tone;

  /// The pill's text. Rendered uppercased regardless of input casing.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tones = Theme.of(context).extension<StatusTones>()!;
    final resolved = statusToneFor(tone, tones);

    final style = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelLarge?.fontSize ?? 14,
      color: resolved.foreground,
      letterSpacing:
          0.16 * (AppTypography.textTheme.labelLarge?.fontSize ?? 14),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resolved.background,
        border: Border.all(color: resolved.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: resolved.foreground,
            ),
          ),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: style),
        ],
      ),
    );
  }
}
