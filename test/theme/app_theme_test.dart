import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_ui/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme is Material 3 and light brightness', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
    });

    test('dark theme is Material 3 and dark brightness', () {
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('light and dark colour schemes differ', () {
      expect(
        AppTheme.light.colorScheme.surface,
        isNot(equals(AppTheme.dark.colorScheme.surface)),
      );
    });
  });
}
