// Pins `android.permission.INTERNET` in the MAIN Android manifest.
//
// Flutter's project scaffolding declares INTERNET only in
// `android/app/src/debug/AndroidManifest.xml` and `.../profile/`. A release
// build therefore ships without it, and because Android merges manifests per
// build type, nothing at compile time complains — the app installs fine and
// then fails every socket at runtime with
// `SocketException: OS Error: Operation not permitted, errno = 1`.
//
// BastionUI is a thin client over `bastion serve` (CLAUDE.md standing rule 7),
// so with no network it does nothing at all. This went unnoticed because the
// entire test suite — unit, widget, e2e and Patrol — runs debug builds, where
// the debug manifest supplies the permission. It was found by manually driving
// a `--release` build on an emulator on 2026-08-18.
//
// This test is the cheap guard that keeps it fixed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest (main)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');

    test('exists', () {
      expect(
        manifest.existsSync(),
        isTrue,
        reason: 'android/app/src/main/AndroidManifest.xml should exist',
      );
    });

    test('declares android.permission.INTERNET', () {
      final contents = manifest.readAsStringSync();
      expect(
        contents.contains(
          '<uses-permission android:name="android.permission.INTERNET"/>',
        ),
        isTrue,
        reason:
            'The MAIN manifest must declare INTERNET. Declaring it only in '
            'the debug/profile manifests ships a release build that cannot '
            'open a socket (EPERM), which makes this thin client useless.',
      );
    });

    test('declares it before <application>, inside <manifest>', () {
      final contents = manifest.readAsStringSync();
      final permissionIndex = contents.indexOf('android.permission.INTERNET');
      final applicationIndex = contents.indexOf('<application');
      expect(permissionIndex, greaterThanOrEqualTo(0));
      expect(applicationIndex, greaterThanOrEqualTo(0));
      expect(
        permissionIndex,
        lessThan(applicationIndex),
        reason: '<uses-permission> is a child of <manifest>, not <application>',
      );
    });
  });
}
