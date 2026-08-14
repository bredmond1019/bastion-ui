/// Literal cool-aurora design tokens for BastionUI (BU.10.A task 2).
///
/// This is the **only** file under `lib/` allowed to contain a `Color(0x...)`
/// literal — every other widget/theme file must read colours from
/// [AppTokens] (directly, or via `StatusTones`/`AppTheme` which are built on
/// top of it). A guard test (`test/theme/no_color_literals_test.dart`, added
/// in a later task of this block) enforces that property.
///
/// Values are copied verbatim from `planning/master-plan.md` → Phase 10 →
/// BU.10.A → *Tokens (authoritative)*, cross-checked against
/// `../bastion-web/app/globals.css`'s `:root` block (the upstream source of
/// truth) and `../bastion-web/docs/design-system.md`.
library;

import 'package:flutter/material.dart';

abstract final class AppTokens {
  // ---------------------------------------------------------------------
  // Ground / surface ladder
  // ---------------------------------------------------------------------

  /// Page ground — the darkest layer (web `--paper`).
  static const Color paper = Color(0xFF06070F);

  /// Panel/card surface, one step lighter than [paper] (web `--surface`).
  static const Color surface = Color(0xFF101426);

  /// A further-muted surface used for nested panels, filled tone chips, etc.
  /// (web `--surface-muted`).
  static const Color surfaceMuted = Color(0xFF171C33);

  /// Hairline border / divider colour (web `--line`).
  static const Color line = Color(0xFF262C46);

  // ---------------------------------------------------------------------
  // Ink (text) ladder
  // ---------------------------------------------------------------------

  /// Primary text colour (web `--ink`).
  static const Color ink = Color(0xFFEEF0FB);

  /// Secondary text colour (web `--ink-soft`).
  static const Color inkSoft = Color(0xFFA6ADCF);

  /// Tertiary / faint text colour (web `--ink-faint`).
  static const Color inkFaint = Color(0xFF737AA0);

  // ---------------------------------------------------------------------
  // Brand accents
  // ---------------------------------------------------------------------

  /// Primary brand hue (web `--primary`).
  static const Color primary = Color(0xFF5D7BFF);

  /// A brighter variant of [primary] for emphasis (web `--primary-strong`).
  static const Color primaryStrong = Color(0xFF8FA1FF);

  /// Tinted primary background fill — intentionally identical to
  /// [surfaceMuted] per the web token table (web `--primary-tint`).
  static const Color primaryTint = Color(0xFF171C33);

  /// Secondary accent hue (web `--accent-2`).
  static const Color accent2 = Color(0xFF58B6FF);

  /// Tertiary accent hue (web `--accent-3`).
  static const Color accent3 = Color(0xFFB08CFF);

  // ---------------------------------------------------------------------
  // Status hues
  // ---------------------------------------------------------------------

  /// "Run complete" success green (web `--run-done`).
  static const Color runDone = Color(0xFF4ADE80);

  /// Warning amber (web `--warning`).
  static const Color warning = Color(0xFFE0B64A);

  /// Destructive / error red. The web token is defined in OKLCH
  /// (`oklch(0.704 0.191 22.216)`); this is its sRGB-space conversion,
  /// carried over as a literal because Flutter's `ColorScheme` and Material
  /// widgets operate in sRGB. Re-derive from the OKLCH value (not from this
  /// hex) if the web token ever changes.
  static const Color destructive = Color(0xFFF4674F);

  // ---------------------------------------------------------------------
  // Radius ladder (dp)
  // ---------------------------------------------------------------------

  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 10;
  static const double radiusXl = 14;
  static const double radiusXxl = 18;
  static const double radiusXxxl = 22;
  static const double radiusXxxxl = 26;

  // ---------------------------------------------------------------------
  // Glow values
  // ---------------------------------------------------------------------

  /// Matches the web `--glow-a` token: [primary] at 26% alpha.
  static Color get glowA => alpha(primary, 0.26);

  /// Matches the web `--glow-b` token: [accent3] at 22% alpha.
  static Color get glowB => alpha(accent3, 0.22);

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Translates the web brand's `/NN` alpha-suffix idiom (e.g. `bg-primary/15`,
  /// `color-mix(in srgb, X 14%, transparent)`) into a Flutter [Color].
  ///
  /// [opacity] is a fraction in `[0, 1]` (i.e. `alpha(primary, 0.15)` is the
  /// equivalent of the web's `bg-primary/15`). Uses [Color.withValues]
  /// rather than the deprecated `Color.withOpacity`.
  static Color alpha(Color color, double opacity) =>
      color.withValues(alpha: opacity);
}
