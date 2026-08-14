import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/tokens.dart';

void main() {
  group('AppTokens', () {
    test('colour palette matches the authoritative hex table', () {
      expect(AppTokens.paper, const Color(0xFF06070F));
      expect(AppTokens.surface, const Color(0xFF101426));
      expect(AppTokens.surfaceMuted, const Color(0xFF171C33));
      expect(AppTokens.line, const Color(0xFF262C46));
      expect(AppTokens.ink, const Color(0xFFEEF0FB));
      expect(AppTokens.inkSoft, const Color(0xFFA6ADCF));
      expect(AppTokens.inkFaint, const Color(0xFF737AA0));
      expect(AppTokens.primary, const Color(0xFF5D7BFF));
      expect(AppTokens.primaryStrong, const Color(0xFF8FA1FF));
      expect(AppTokens.primaryTint, const Color(0xFF171C33));
      expect(AppTokens.accent2, const Color(0xFF58B6FF));
      expect(AppTokens.accent3, const Color(0xFFB08CFF));
      expect(AppTokens.runDone, const Color(0xFF4ADE80));
      expect(AppTokens.warning, const Color(0xFFE0B64A));
      expect(AppTokens.destructive, const Color(0xFFF4674F));
    });

    test('radius ladder matches the dp values in the block definition', () {
      expect(AppTokens.radiusSm, 6);
      expect(AppTokens.radiusMd, 8);
      expect(AppTokens.radiusLg, 10);
      expect(AppTokens.radiusXl, 14);
      expect(AppTokens.radiusXxl, 18);
      expect(AppTokens.radiusXxxl, 22);
      expect(AppTokens.radiusXxxxl, 26);
    });

    test('glowA is primary at 26% alpha (matches web --glow-a)', () {
      final glowA = AppTokens.glowA;
      expect(glowA.r, AppTokens.primary.r);
      expect(glowA.g, AppTokens.primary.g);
      expect(glowA.b, AppTokens.primary.b);
      expect(glowA.a, closeTo(0.26, 0.001));
    });

    test('glowB is accent3 at 22% alpha (matches web --glow-b)', () {
      final glowB = AppTokens.glowB;
      expect(glowB.r, AppTokens.accent3.r);
      expect(glowB.g, AppTokens.accent3.g);
      expect(glowB.b, AppTokens.accent3.b);
      expect(glowB.a, closeTo(0.22, 0.001));
    });

    test('alpha() applies the given opacity to the given colour', () {
      final tinted = AppTokens.alpha(AppTokens.primary, 0.15);
      expect(tinted.r, AppTokens.primary.r);
      expect(tinted.g, AppTokens.primary.g);
      expect(tinted.b, AppTokens.primary.b);
      expect(tinted.a, closeTo(0.15, 0.001));
    });
  });
}
