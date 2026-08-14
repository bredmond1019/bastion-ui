import 'package:bastion_ui/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTypography.textTheme', () {
    final textTheme = AppTypography.textTheme;

    test('display/headline/title roles use Inter, bold, tight tracking', () {
      final headingRoles = <TextStyle?>[
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.titleSmall,
      ];

      for (final style in headingRoles) {
        expect(style, isNotNull);
        expect(style!.fontFamily, 'Inter');
        expect(style.fontWeight, FontWeight.w700);
        expect(
          style.letterSpacing,
          isNotNull,
          reason: 'heading roles must carry tight (negative) letter-spacing',
        );
        expect(style.letterSpacing!, lessThan(0));
      }
    });

    test('body roles use Source Sans 3 at regular weight', () {
      final bodyRoles = <TextStyle?>[
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
      ];

      for (final style in bodyRoles) {
        expect(style, isNotNull);
        expect(style!.fontFamily, 'SourceSans3');
        expect(style.fontWeight, FontWeight.w400);
      }
    });

    test(
      'label roles use Source Sans 3 at medium weight (labelLarge/Small)',
      () {
        expect(textTheme.labelLarge?.fontFamily, 'SourceSans3');
        expect(textTheme.labelLarge?.fontWeight, FontWeight.w500);
        expect(textTheme.labelSmall?.fontFamily, 'SourceSans3');
        expect(textTheme.labelSmall?.fontWeight, FontWeight.w500);
      },
    );

    test('labelMedium carries the mono brand-label treatment', () {
      final labelMedium = textTheme.labelMedium;
      expect(labelMedium, isNotNull);
      expect(labelMedium!.fontFamily, 'JetBrainsMono');
      expect(labelMedium.letterSpacing, greaterThan(0));
    });

    test('every TextTheme role has an explicit brand family assigned', () {
      // No trailing TextTheme.apply(fontFamily: ...) is used, since that
      // would clobber the per-role families set above uniformly. Assert a
      // representative role from each family group stays distinct.
      expect(textTheme.headlineMedium?.fontFamily, 'Inter');
      expect(textTheme.bodyMedium?.fontFamily, 'SourceSans3');
      expect(textTheme.labelMedium?.fontFamily, 'JetBrainsMono');
    });
  });

  group('AppTypography.mono', () {
    test('uses the JetBrains Mono family at regular weight', () {
      expect(AppTypography.mono.fontFamily, 'JetBrainsMono');
      expect(AppTypography.mono.fontWeight, FontWeight.w400);
    });
  });

  group('AppTypography.labelMedium', () {
    test('is mono with positive letter-spacing (the label-only treatment)', () {
      expect(AppTypography.labelMedium.fontFamily, 'JetBrainsMono');
      expect(AppTypography.labelMedium.letterSpacing, greaterThan(0));
    });
  });
}
