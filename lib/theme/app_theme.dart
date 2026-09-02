/// The single dark [ThemeData] for BastionUI (BU.10.A task 5).
///
/// Replaces the generated-from-seed light/dark pair (`ColorScheme.fromSeed`)
/// with an explicitly specified dark-only Material 3 theme built from
/// [AppTokens]. BastionUI is a tailnet-only operator surface, not a
/// general-audience app — it renders dark regardless of the host device's
/// system theme (see `main.dart`'s `themeMode: ThemeMode.dark`).
library;

import 'package:flutter/material.dart';

import 'status_tones.dart';
import 'tokens.dart';
import 'typography.dart';

abstract final class AppTheme {
  /// The app's one and only [ThemeData]. Every [ColorScheme] slot below is
  /// assigned explicitly from [AppTokens] — no `ColorScheme.fromSeed` tonal
  /// generation. Mirrors the web ground ladder (paper → surface →
  /// surfaceMuted → line) and the `StatusBadge` tone table via the
  /// [StatusTones] extension.
  ///
  /// Built once and cached (`late final`, not a getter): `ThemeData`'s
  /// `navigationBarTheme` carries `WidgetStateProperty.resolveWith` closures,
  /// and two separately-constructed closures are never `==` to each other
  /// even with identical bodies — so a getter that rebuilds `ThemeData` on
  /// every access would make `AppTheme.dark == AppTheme.dark` false and
  /// break every `equals(AppTheme.dark)` comparison in the test suite.
  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppTokens.primary,
      onPrimary: AppTokens.paper,
      primaryContainer: AppTokens.primaryTint,
      onPrimaryContainer: AppTokens.ink,
      secondary: AppTokens.accent2,
      onSecondary: AppTokens.paper,
      secondaryContainer: AppTokens.surfaceMuted,
      onSecondaryContainer: AppTokens.ink,
      tertiary: AppTokens.accent3,
      onTertiary: AppTokens.paper,
      tertiaryContainer: AppTokens.surfaceMuted,
      onTertiaryContainer: AppTokens.ink,
      error: AppTokens.destructive,
      onError: AppTokens.paper,
      errorContainer: AppTokens.surfaceMuted,
      onErrorContainer: AppTokens.ink,
      surface: AppTokens.surface,
      onSurface: AppTokens.ink,
      surfaceContainerHighest: AppTokens.surfaceMuted,
      onSurfaceVariant: AppTokens.inkSoft,
      outline: AppTokens.line,
      outlineVariant: AppTokens.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppTokens.ink,
      onInverseSurface: AppTokens.paper,
      inversePrimary: AppTokens.primaryStrong,
      surfaceTint: AppTokens.primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppTokens.paper,
      textTheme: AppTypography.textTheme,
      extensions: <ThemeExtension<dynamic>>[StatusTones.dark],
      cardTheme: CardThemeData(
        color: AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusXl),
          side: const BorderSide(color: AppTokens.line),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.surface,
        foregroundColor: AppTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppTokens.surface,
        indicatorColor: AppTokens.alpha(AppTokens.primary, 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppTokens.primary : AppTokens.inkSoft,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppTokens.primary : AppTokens.inkSoft,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppTokens.surface,
        contentTextStyle: const TextStyle(color: AppTokens.ink),
        actionTextColor: AppTokens.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          side: const BorderSide(color: AppTokens.line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppTokens.line, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: _inputBorder,
        enabledBorder: _inputBorder,
        focusedBorder: _inputBorder.copyWith(
          borderSide: const BorderSide(color: AppTokens.primary, width: 2),
        ),
      ),
    );
  }

  /// Shared hairline border for [InputDecorationTheme.border]/`enabledBorder`
  /// — line-coloured by default, primary-coloured on focus.
  static final OutlineInputBorder _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    borderSide: const BorderSide(color: AppTokens.line),
  );
}
