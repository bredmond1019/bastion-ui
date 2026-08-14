/// The six semantic status tones as a [ThemeExtension] (BU.10.A task 3).
///
/// Mirrors `../bastion-web/components/ui/status-badge.tsx`'s `tone` variant
/// table: each tone carries the foreground/background/border triplet the
/// web `StatusBadge` renders. Values are derived from [AppTokens] — this
/// file introduces no new `Color(0x...)` literals; `AppTokens` remains the
/// only allowed source of those (see its doc comment).
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// One semantic tone's colour triplet: text, fill, and hairline border.
@immutable
final class StatusTone {
  const StatusTone({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;

  static StatusTone lerp(StatusTone a, StatusTone b, double t) {
    return StatusTone(
      foreground: Color.lerp(a.foreground, b.foreground, t) ?? a.foreground,
      background: Color.lerp(a.background, b.background, t) ?? a.background,
      border: Color.lerp(a.border, b.border, t) ?? a.border,
    );
  }
}

/// A [ThemeExtension] carrying BastionUI's six semantic status tones:
/// `neutral`, `info`, `active`, `success`, `warning`, `danger`.
///
/// Read it via the [statusTones] `BuildContext`/`ThemeData` accessors below
/// rather than a raw `Theme.of(context).extension<StatusTones>()!` — the
/// accessors fall back to [StatusTones.dark] instead of throwing when the
/// extension has not been registered (e.g. a widget test that builds a bare
/// `MaterialApp` without `AppTheme.dark`).
@immutable
final class StatusTones extends ThemeExtension<StatusTones> {
  const StatusTones({
    required this.neutral,
    required this.info,
    required this.active,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final StatusTone neutral;
  final StatusTone info;
  final StatusTone active;
  final StatusTone success;
  final StatusTone warning;
  final StatusTone danger;

  /// The (only) instance BastionUI ships — built from [AppTokens], matching
  /// the web `StatusBadge` tone table verbatim.
  static final StatusTones dark = StatusTones(
    neutral: const StatusTone(
      foreground: AppTokens.inkSoft,
      background: AppTokens.surfaceMuted,
      border: AppTokens.line,
    ),
    info: StatusTone(
      foreground: AppTokens.primary,
      background: AppTokens.alpha(AppTokens.primary, 0.15),
      border: AppTokens.alpha(AppTokens.primary, 0.30),
    ),
    active: StatusTone(
      foreground: AppTokens.accent2,
      background: AppTokens.alpha(AppTokens.accent2, 0.15),
      border: AppTokens.alpha(AppTokens.accent2, 0.40),
    ),
    success: StatusTone(
      foreground: AppTokens.accent3,
      background: AppTokens.alpha(AppTokens.accent3, 0.15),
      border: AppTokens.alpha(AppTokens.accent3, 0.40),
    ),
    warning: StatusTone(
      foreground: AppTokens.warning,
      background: AppTokens.alpha(AppTokens.warning, 0.15),
      border: AppTokens.alpha(AppTokens.warning, 0.40),
    ),
    danger: StatusTone(
      foreground: AppTokens.destructive,
      background: AppTokens.alpha(AppTokens.destructive, 0.15),
      border: AppTokens.alpha(AppTokens.destructive, 0.40),
    ),
  );

  @override
  StatusTones copyWith({
    StatusTone? neutral,
    StatusTone? info,
    StatusTone? active,
    StatusTone? success,
    StatusTone? warning,
    StatusTone? danger,
  }) {
    return StatusTones(
      neutral: neutral ?? this.neutral,
      info: info ?? this.info,
      active: active ?? this.active,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  StatusTones lerp(ThemeExtension<StatusTones>? other, double t) {
    if (other is! StatusTones) return this;
    return StatusTones(
      neutral: StatusTone.lerp(neutral, other.neutral, t),
      info: StatusTone.lerp(info, other.info, t),
      active: StatusTone.lerp(active, other.active, t),
      success: StatusTone.lerp(success, other.success, t),
      warning: StatusTone.lerp(warning, other.warning, t),
      danger: StatusTone.lerp(danger, other.danger, t),
    );
  }
}

/// Convenience accessors so widgets read [StatusTones] without ceremony and
/// without ever null-asserting a missing extension.
extension StatusTonesTheme on ThemeData {
  /// This [ThemeData]'s [StatusTones] extension, or [StatusTones.dark] if
  /// none was registered.
  StatusTones get statusTones => extension<StatusTones>() ?? StatusTones.dark;
}

extension StatusTonesContext on BuildContext {
  /// The ambient [StatusTones], or [StatusTones.dark] if the ambient theme
  /// has not registered the extension.
  StatusTones get statusTones => Theme.of(this).statusTones;
}
