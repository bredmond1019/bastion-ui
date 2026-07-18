/// Gating unit tests for the pure decision logic in
/// [bastion_serve_harness.dart]. Deliberately NOT tagged `e2e` — this file
/// spawns no subprocess and exercises only the strict-mode env parse, so it
/// runs as part of the normal gating suite (`flutter test --exclude-tags
/// e2e`). The subprocess-driving behavior is covered by the `e2e`-tagged
/// `serve_contract_e2e_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'bastion_serve_harness.dart';

void main() {
  group('bastionE2eRequireBinary', () {
    test('is false when the env var is unset', () {
      expect(bastionE2eRequireBinary(const {}), isFalse);
    });

    test('is false when the env var is empty', () {
      expect(
        bastionE2eRequireBinary(const {bastionE2eRequireEnvVar: ''}),
        isFalse,
      );
    });

    for (final truthy in const ['1', 'true', 'yes', 'on']) {
      test('is true for the truthy value "$truthy"', () {
        expect(
          bastionE2eRequireBinary({bastionE2eRequireEnvVar: truthy}),
          isTrue,
        );
      });
    }

    test('is case- and whitespace-insensitive for truthy values', () {
      expect(
        bastionE2eRequireBinary(const {bastionE2eRequireEnvVar: '  TRUE  '}),
        isTrue,
      );
      expect(
        bastionE2eRequireBinary(const {bastionE2eRequireEnvVar: 'On'}),
        isTrue,
      );
    });

    for (final falsy in const ['0', 'false', 'no', 'off', 'maybe']) {
      test('is false for the non-truthy value "$falsy"', () {
        expect(
          bastionE2eRequireBinary({bastionE2eRequireEnvVar: falsy}),
          isFalse,
        );
      });
    }
  });
}
