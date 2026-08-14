/// The brand `TextTheme` built on the vendored type trio (BU.10.A task 4).
///
/// Three families, each with a fixed role, mirroring the web brand:
///  - **Inter** — display/headline/title roles, bold (700), tight
///    letter-spacing (web `font-heading font-bold tracking-tight`).
///  - **Source Sans 3** — body and label roles, the default reading face.
///  - **JetBrains Mono** — reserved for monospace contexts: the terminal
///    pane, and block IDs / short labels elsewhere in the app.
///
/// Sizes deliberately use the Material 3 defaults (the CALM gear), not the
/// web's dense desk-and-mouse ladder (`--text-dense-*`, 10.5–13.5px, 2px
/// radii, 48px rows) — that gear is for a mouse at desk distance and must
/// not be ported to a phone screen. See `planning/master-plan.md` → Phase
/// 10 → BU.10.A → "Deliberately out of scope".
///
/// Brand label rule (mirrored from the web guard test,
/// `../bastion-web/tests/styles/ornament-guard.test.ts`): **mono type,
/// uppercase casing, and positive letter-spacing are permitted on LABELS
/// only — never on body content.** [AppTypography.mono] and
/// [AppTypography.labelMedium] exist to carry that treatment; do not reuse
/// them for prose.
library;

import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const String _headingFamily = 'Inter';
  static const String _bodyFamily = 'SourceSans3';
  static const String _monoFamily = 'JetBrainsMono';

  /// The full brand [TextTheme], built on Material 3's default type scale
  /// (calm gear) with family/weight/letter-spacing overridden per role.
  ///
  /// Display/headline/title roles use [_headingFamily] at bold (700) with
  /// tight letter-spacing; body/label roles use [_bodyFamily] at regular
  /// (400) / medium (500).
  static TextTheme get textTheme {
    final base = Typography.material2021(
      platform: TargetPlatform.android,
    ).white;
    // Every one of Material 3's 15 TextTheme roles is overridden below with
    // an explicit fontFamily, so no trailing `.apply(fontFamily: ...)` is
    // used — `TextTheme.apply` sets one family across every role uniformly,
    // which would silently clobber the heading (Inter) and label
    // (JetBrainsMono) families back to the body face.
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontFamily: _bodyFamily,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontFamily: _bodyFamily,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontFamily: _bodyFamily,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontFamily: _bodyFamily,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: labelMedium,
      labelSmall: base.labelSmall?.copyWith(
        fontFamily: _bodyFamily,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// The brand label treatment: mono, uppercase-ready, positive
  /// letter-spacing. Reserved for LABELS only (eyebrow text, block IDs,
  /// short status/session identifiers) — never for prose or body content.
  /// Mirrors the web brand rule enforced by `ornament-guard.test.ts`.
  static const TextStyle labelMedium = TextStyle(
    fontFamily: _monoFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    letterSpacing: 0.8,
  );

  /// The named mono style for use by the terminal pane and by block
  /// IDs / labels in later blocks. Plain (no letter-spacing or casing
  /// applied) — callers that need the LABEL treatment above should use
  /// [labelMedium] instead, or apply uppercase/tracking themselves and note
  /// why in a doc comment, per the brand label rule.
  static const TextStyle mono = TextStyle(
    fontFamily: _monoFamily,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.4,
  );
}
