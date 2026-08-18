/// Service-level e2e test: boots a REAL `bastion serve` subprocess with the
/// Section 18 engine mount enabled (via [BastionServeHarness.start]'s
/// `engineMount: true`), and drives the real, non-mocked [EngineApi]
/// against it — no fakes, no mocks.
///
/// Covers two things no unit test over `FakeHttpTransport` can:
///   - `GET /workflows` against a genuinely engine-mounted server returns a
///     non-empty registry, and a deliberately wrong `X-API-Key` yields
///     [EngineStatus.unauthorized] rather than throwing.
///   - `probeMount()` against the DEFAULT harness (engine env stripped, per
///     `bastion_serve_harness.dart`'s documented default) reports
///     [EngineStatus.notMounted] — not [EngineStatus.unauthorized], not
///     [EngineStatus.available]. This is the branch easiest to get wrong
///     (an unmounted server has no `/workflows` route at all, distinct from
///     a mounted one rejecting a bad key) and the only place it can be
///     checked against a real server rather than a fake.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`.
///
/// Self-skips (via `markTestSkipped`) — visibly, never a silent pass — when
/// no engine-mounted server is obtainable in this environment: either no
/// `bastion` binary can be located, or `DATABASE_URL` /
/// `BASTION_ENGINE_API_KEY` are not both set in the parent process
/// environment (see [bastionServeHarnessEngineMountAvailable]).
///
/// The engine API key itself is read from the real process environment at
/// runtime only — never hardcoded, never logged, never interpolated into
/// any string in this file. Only [_wrongEngineKey], a deliberately-invalid
/// sentinel, appears as a literal.
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/engine_api.dart';

import 'bastion_serve_harness.dart';

/// A deliberately-wrong engine API key for driving the unauthorized path.
const _wrongEngineKey = 'e2e-wrong-engine-key-does-not-exist';

void main() {
  group('engine read e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test(
      'real EngineApi reads the real workflow registry from an '
      'engine-mounted server; a wrong key is unauthorized, not a crash',
      () async {
        if (!bastionServeHarnessEngineMountAvailable()) {
          const whereChecked =
              'checked BASTION_BIN, ../bastion/target/release/bastion, '
              '../bastion/target/debug/bastion, and the parent environment '
              'for DATABASE_URL + BASTION_ENGINE_API_KEY';
          if (bastionE2eRequireBinary()) {
            fail(
              '$bastionE2eRequireEnvVar is set but no engine-mounted '
              'bastion serve could be obtained ($whereChecked) — build a '
              'binary with `cargo build -p bastion` in ../bastion and '
              'export DATABASE_URL + BASTION_ENGINE_API_KEY, or set '
              'BASTION_BIN.',
            );
          }
          markTestSkipped(
            'no engine-mounted bastion serve obtainable ($whereChecked) — '
            'skipping engine read e2e test (set '
            '$bastionE2eRequireEnvVar=1 to make this a hard failure '
            'instead)',
          );
          return;
        }

        final engineKey = Platform.environment['BASTION_ENGINE_API_KEY']!;

        harness = await BastionServeHarness.start(engineMount: true);
        final h = harness;
        if (h == null) {
          // bastionServeHarnessEngineMountAvailable() already checked the
          // binary is locatable, but guard against a race/removal between
          // the two calls rather than assuming h is non-null.
          markTestSkipped(
            'bastion binary became unavailable between the availability '
            'check and start() — skipping engine read e2e test',
          );
          return;
        }

        // --- Real key: registry read succeeds --------------------------
        final goodClient = EngineApi(
          host: h.host,
          port: h.port,
          key: engineKey,
        );
        try {
          final types = await goodClient.getWorkflows();
          expect(types, isA<List<String>>());
          expect(types, isNotEmpty);

          final status = await goodClient.probeMount();
          expect(status, EngineStatus.available);
        } finally {
          goodClient.dispose();
        }

        // --- Wrong key: unauthorized, not a crash -----------------------
        final wrongClient = EngineApi(
          host: h.host,
          port: h.port,
          key: _wrongEngineKey,
        );
        try {
          final wrongStatus = await wrongClient.probeMount();
          expect(wrongStatus, EngineStatus.unauthorized);
        } finally {
          wrongClient.dispose();
        }

        await h.stop();
        harness = null;

        // --- Default harness (engine stripped): notMounted, for real ----
        final defaultHarness = await BastionServeHarness.start();
        harness = defaultHarness;
        final dh = defaultHarness;
        if (dh == null) {
          markTestSkipped(
            'bastion binary became unavailable while starting the default '
            '(engine-stripped) harness — skipping the notMounted assertion',
          );
          return;
        }
        final notMountedClient = EngineApi(
          host: dh.host,
          port: dh.port,
          key: engineKey,
        );
        try {
          final notMountedStatus = await notMountedClient.probeMount();
          expect(notMountedStatus, EngineStatus.notMounted);
          expect(notMountedStatus, isNot(EngineStatus.unauthorized));
          expect(notMountedStatus, isNot(EngineStatus.available));
        } finally {
          notMountedClient.dispose();
        }
      },
    );
  });
}
