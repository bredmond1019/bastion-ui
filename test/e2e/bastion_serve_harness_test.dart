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

  group('bastionServeHarnessChildEnvironment', () {
    test('always includes PATH, defaulting to empty when absent', () {
      expect(bastionServeHarnessChildEnvironment(const {}), {'PATH': ''});
    });

    test('forwards a present, non-empty PATH', () {
      expect(bastionServeHarnessChildEnvironment(const {'PATH': '/usr/bin'}), {
        'PATH': '/usr/bin',
      });
    });

    test('forwards LANG and LC_ALL when present and non-empty', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'LANG': 'en_US.UTF-8',
          'LC_ALL': 'C.UTF-8',
        }),
        {'PATH': '/usr/bin', 'LANG': 'en_US.UTF-8', 'LC_ALL': 'C.UTF-8'},
      );
    });

    test('omits LANG/LC_ALL when absent from the parent environment', () {
      expect(bastionServeHarnessChildEnvironment(const {'PATH': '/usr/bin'}), {
        'PATH': '/usr/bin',
      });
    });

    test('omits LANG/LC_ALL when present but empty', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'LANG': '',
          'LC_ALL': '',
        }),
        {'PATH': '/usr/bin'},
      );
    });

    test('never forwards DATABASE_URL or other engine-api-key vars', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'LANG': 'en_US.UTF-8',
          'DATABASE_URL': 'postgres://example',
          'BASTION_ENGINE_API_KEY': 'secret',
        }),
        {'PATH': '/usr/bin', 'LANG': 'en_US.UTF-8'},
      );
    });

    test('still never forwards engine vars when forwardEngineEnv is omitted '
        '(default false)', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'DATABASE_URL': 'postgres://example',
          'BASTION_ENGINE_API_KEY': 'secret',
        }),
        {'PATH': '/usr/bin'},
      );
    });

    test('opt-in forwardEngineEnv forwards DATABASE_URL and '
        'BASTION_ENGINE_API_KEY from the parent environment', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'LANG': 'en_US.UTF-8',
          'DATABASE_URL': 'postgres://example',
          'BASTION_ENGINE_API_KEY': 'secret',
        }, true),
        {
          'PATH': '/usr/bin',
          'LANG': 'en_US.UTF-8',
          'DATABASE_URL': 'postgres://example',
          'BASTION_ENGINE_API_KEY': 'secret',
        },
      );
    });

    test('opt-in forwardEngineEnv omits engine vars that are absent or empty '
        'in the parent environment', () {
      expect(
        bastionServeHarnessChildEnvironment(const {
          'PATH': '/usr/bin',
          'DATABASE_URL': '',
        }, true),
        {'PATH': '/usr/bin'},
      );
    });
  });

  group('bastionServeHarnessEngineMountAvailable', () {
    test('is false when neither engine env var is present', () {
      expect(
        bastionServeHarnessEngineMountAvailable(const {'PATH': '/usr/bin'}),
        isFalse,
      );
    });

    test('is false when only one of the two engine env vars is present', () {
      expect(
        bastionServeHarnessEngineMountAvailable(const {
          'PATH': '/usr/bin',
          'DATABASE_URL': 'postgres://example',
        }),
        isFalse,
      );
    });

    test('is false when an engine env var is present but empty', () {
      expect(
        bastionServeHarnessEngineMountAvailable(const {
          'PATH': '/usr/bin',
          'DATABASE_URL': 'postgres://example',
          'BASTION_ENGINE_API_KEY': '',
        }),
        isFalse,
      );
    });

    // Binary-availability is deliberately not exercised through an injected
    // env here: BastionServeHarness.locateBinary() always reads the real
    // `Platform.environment` / repo-relative candidates (by design — see
    // its own doc), so it isn't independently fakeable via the
    // parentEnvironment map this function accepts for the env-var half of
    // the check. That half is exercised for real by every e2e test that
    // calls BastionServeHarness.start (self-skips when locateBinary()
    // returns null).
  });
}
