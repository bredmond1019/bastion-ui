import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launcher icon source asset exists', () {
    expect(File('assets/icon/app_icon.png').existsSync(), isTrue);
  });

  test(
    'pubspec declares flutter_launcher_icons config pointing at the source asset',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('flutter_launcher_icons:'), isTrue);
      expect(pubspec.contains('assets/icon/app_icon.png'), isTrue);
    },
  );

  test('generated mipmap launcher icons are non-empty for every density', () {
    const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    for (final density in densities) {
      final file = File(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'missing mipmap-$density/ic_launcher.png',
      );
      expect(
        file.lengthSync(),
        greaterThan(0),
        reason: 'mipmap-$density/ic_launcher.png is empty',
      );
    }
  });
}
