// Guard test (BU.10.A task 6): fails if a `Color(0x...)` literal appears
// anywhere under `lib/` outside `lib/theme/`.
//
// `lib/theme/tokens.dart` is the ONLY file allowed to declare a raw colour
// literal (see its doc comment); every other widget/theme file must read
// colours from `AppTokens`/`StatusTones`. This test enforces that property
// directly against the source tree so a `Color(0x...)` literal creeping
// back into a widget during BU.10.C fails the suite instead of shipping.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no Color(0x...) literal exists under lib/ outside lib/theme/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final literalPattern = RegExp(r'Color\(0x');
    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      // Normalize to forward-slash relative path for the theme/ exclusion
      // check, so this works identically on macOS/Linux CI.
      final normalized = entity.path.replaceAll(r'\', '/');
      final libIndex = normalized.indexOf('lib/');
      final relPath = libIndex == -1
          ? normalized
          : normalized.substring(libIndex + 'lib/'.length);
      if (relPath.startsWith('theme/')) continue;

      final content = entity.readAsStringSync();
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (literalPattern.hasMatch(lines[i])) {
          offenders.add('lib/$relPath:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found Color(0x...) literal(s) outside lib/theme/ — read from '
          'AppTokens/StatusTones instead:\n${offenders.join('\n')}',
    );
  });
}
