/// Centralised light + dark [ThemeData] for BastionUI (BU.4.A).
///
/// Both variants are Material 3 and share the blueGrey seed the app shipped
/// with; the dark variant is a genuine dark scheme (Brightness.dark), not the
/// light one dimmed. `main.dart` supplies these as `theme`/`darkTheme` with
/// `themeMode: ThemeMode.system`.
library;

import 'package:flutter/material.dart';

abstract final class AppTheme {
  /// Seed colour shared by both brightness variants (matches the original
  /// inline theme in `main.dart`).
  static const Color seed = Colors.blueGrey;

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    useMaterial3: true,
  );

  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
