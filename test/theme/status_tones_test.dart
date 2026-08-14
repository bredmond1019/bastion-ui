import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusTones', () {
    test('all six tones resolve from a ThemeData carrying the extension', () {
      final theme = ThemeData.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[StatusTones.dark],
      );
      final tones = theme.extension<StatusTones>();

      expect(tones, isNotNull);
      expect(tones!.neutral.foreground, AppTokens.inkSoft);
      expect(tones.info.foreground, AppTokens.primary);
      expect(tones.active.foreground, AppTokens.accent2);
      expect(tones.success.foreground, AppTokens.accent3);
      expect(tones.warning.foreground, AppTokens.warning);
      expect(tones.danger.foreground, AppTokens.destructive);
    });

    test(
      'neutral tone matches the web tone table (border/surface-muted/ink-soft)',
      () {
        final neutral = StatusTones.dark.neutral;
        expect(neutral.border, AppTokens.line);
        expect(neutral.background, AppTokens.surfaceMuted);
        expect(neutral.foreground, AppTokens.inkSoft);
      },
    );

    test('lerp at t=0 and t=1 returns the endpoints', () {
      const a = StatusTones(
        neutral: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
        info: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
        active: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
        success: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
        warning: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
        danger: StatusTone(
          foreground: Colors.black,
          background: Colors.black,
          border: Colors.black,
        ),
      );
      final b = StatusTones.dark;

      final atStart = a.lerp(b, 0);
      final atEnd = a.lerp(b, 1);

      expect(atStart.neutral.foreground, Colors.black);
      expect(atStart.info.background, Colors.black);
      expect(atEnd.neutral.foreground, b.neutral.foreground);
      expect(atEnd.danger.border, b.danger.border);
    });

    test('lerp returns this when other is not a StatusTones', () {
      final result = StatusTones.dark.lerp(null, 0.5);
      expect(result, same(StatusTones.dark));
    });

    test('copyWith overrides only the given tone', () {
      const replacement = StatusTone(
        foreground: Colors.red,
        background: Colors.red,
        border: Colors.red,
      );
      final updated = StatusTones.dark.copyWith(danger: replacement);

      expect(updated.danger, replacement);
      expect(updated.neutral, StatusTones.dark.neutral);
    });

    testWidgets(
      'ThemeData.statusTones falls back to StatusTones.dark when unregistered',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(Theme.of(capturedContext).statusTones, StatusTones.dark);
        expect(capturedContext.statusTones, StatusTones.dark);
      },
    );

    testWidgets('BuildContext.statusTones resolves the registered extension', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: <ThemeExtension<dynamic>>[StatusTones.dark],
          ),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(capturedContext.statusTones, StatusTones.dark);
    });
  });
}
