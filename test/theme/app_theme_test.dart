import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/theme/tokens.dart';

void main() {
  group('AppTheme', () {
    test('dark theme is Material 3 and dark brightness', () {
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('named ColorScheme slots equal the expected AppTokens', () {
      final scheme = AppTheme.dark.colorScheme;
      expect(scheme.primary, AppTokens.primary);
      expect(scheme.onPrimary, AppTokens.paper);
      expect(scheme.primaryContainer, AppTokens.primaryTint);
      expect(scheme.secondary, AppTokens.accent2);
      expect(scheme.tertiary, AppTokens.accent3);
      expect(scheme.surface, AppTokens.surface);
      expect(scheme.onSurface, AppTokens.ink);
      expect(scheme.surfaceContainerHighest, AppTokens.surfaceMuted);
      expect(scheme.outline, AppTokens.line);
      expect(scheme.outlineVariant, AppTokens.line);
      expect(scheme.error, AppTokens.destructive);
      expect(scheme.onError, AppTokens.paper);
    });

    test('scaffold background is paper, distinct from surface', () {
      expect(AppTheme.dark.scaffoldBackgroundColor, AppTokens.paper);
      expect(
        AppTheme.dark.scaffoldBackgroundColor,
        isNot(equals(AppTheme.dark.colorScheme.surface)),
      );
    });

    test('the StatusTones extension is registered', () {
      final tones = AppTheme.dark.extension<StatusTones>();
      expect(tones, isNotNull);
      expect(tones, same(StatusTones.dark));
    });

    test('component themes are attached (card, app bar, divider, input)', () {
      final theme = AppTheme.dark;
      expect(theme.cardTheme.color, AppTokens.surface);
      expect(theme.appBarTheme.backgroundColor, AppTokens.surface);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.dividerTheme.color, AppTokens.line);
      expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
    });

    test(
      'textTheme carries the brand roles (heading family on titleLarge)',
      () {
        expect(AppTheme.dark.textTheme.titleLarge?.fontFamily, 'Inter');
        expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, 'SourceSans3');
      },
    );
  });
}
