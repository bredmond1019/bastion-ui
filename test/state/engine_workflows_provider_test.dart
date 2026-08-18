// Unit tests for `engine_workflows_provider.dart` (`BU.12.E` task 3).
//
// Covers this task's acceptance criteria:
//   1. workflow types come from the live registry with no hardcoded list
//      anywhere — asserted by round-tripping an unusual fixture list
//      through [EngineWorkflowsLoaded] verbatim;
//   2. not-configured, not-mounted, and genuinely-empty are distinguishable
//      states — three separate tests, none of which collapse into the same
//      [EngineWorkflowsState] member/[EngineStatus] value;
//   3. Rule 7 — a sentinel engine key never appears in any produced state
//      (including the `unreachable` [EngineWorkflowsUnavailable.error]
//      diagnostic).
//
// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/engine_api.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/engine_workflows_provider.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fake FlutterSecureStorage (mirrors test/state/connection_provider_test.dart)
// ---------------------------------------------------------------------------

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }
}

const _sentinelKey = 'sentinel-engine-key-do-not-leak';

Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Builds a [ProviderContainer] with [storage] seeded, [transport] wired
/// into every [EngineApi] this provider tree constructs, and
/// `connectionProvider`'s async config load already resolved (pumped)
/// before the caller reads/watches [engineWorkflowsProvider] — avoiding the
/// race between `connectionProvider`'s own `_load()` and this notifier's
/// synchronous `connectionProvider` read at the top of `refresh()`.
Future<ProviderContainer> _makeReadyContainer({
  required _FakeSecureStorage storage,
  required FakeHttpTransport transport,
}) async {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      engineApiFactoryProvider.overrideWithValue(
        ({required host, required port, required key}) =>
            EngineApi(host: host, port: port, key: key, transport: transport),
      ),
    ],
  );
  // Force connectionProvider to construct and let its async _load()
  // resolve before anything reads it synchronously.
  container.read(connectionProvider);
  await pump();
  return container;
}

void main() {
  group('engineWorkflowsProvider', () {
    late _FakeSecureStorage storage;
    late FakeHttpTransport transport;
    late ProviderContainer container;

    setUp(() {
      storage = _FakeSecureStorage();
      storage.store['bastion.server.host'] = 'test-host';
      storage.store['bastion.server.port'] = '4317';
      transport = FakeHttpTransport();
    });

    tearDown(() => container.dispose());

    test('initial state is loading before the probe resolves', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      transport.on('GET', '/workflows', status: 200, body: ['a']);
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsLoading>());
    });

    test('no engine key configured -> notConfigured, zero requests', () async {
      // No 'bastion.auth.engine_key' entry at all.
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsUnavailable>());
      expect(
        (state as EngineWorkflowsUnavailable).status,
        EngineStatus.notConfigured,
      );
      expect(transport.calls, isEmpty);
    });

    test('engine mounted but unreachable route -> notMounted', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      transport.on('GET', '/workflows', status: 404, body: 'not found');
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsUnavailable>());
      expect(
        (state as EngineWorkflowsUnavailable).status,
        EngineStatus.notMounted,
      );
    });

    test('rejected key -> unauthorized, distinct from notMounted', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      transport.on(
        'GET',
        '/workflows',
        status: 401,
        body: {'error': 'unauthorized'},
      );
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsUnavailable>());
      expect(
        (state as EngineWorkflowsUnavailable).status,
        EngineStatus.unauthorized,
      );
    });

    test(
      'available with an empty registry -> Loaded([]), not Unavailable',
      () async {
        storage.store['bastion.auth.engine_key'] = _sentinelKey;
        transport.on('GET', '/workflows', status: 200, body: <String>[]);
        container = await _makeReadyContainer(
          storage: storage,
          transport: transport,
        );
        container.read(engineWorkflowsProvider); // trigger construction
        await pump();

        final state = container.read(engineWorkflowsProvider);
        expect(state, isA<EngineWorkflowsLoaded>());
        expect((state as EngineWorkflowsLoaded).types, isEmpty);
      },
    );

    test('available with types -> Loaded carries the server list verbatim, '
        'sorted, no hardcoded types', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      // Deliberately unusual names — if these ever appeared hardcoded
      // anywhere in lib/ this test would still be the only place they're
      // introduced, so a pass here is real evidence the list came from
      // the transport, not a compiled-in constant.
      final fixtureTypes = ['zz_zebra_flow', 'aa_aardvark_flow'];
      transport.on('GET', '/workflows', status: 200, body: fixtureTypes);
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsLoaded>());
      expect((state as EngineWorkflowsLoaded).types, [...fixtureTypes]..sort());
    });

    test('refresh() re-probes and can flip Loaded -> Unavailable', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      // Initial construction consumes TWO calls (probeMount, then
      // getWorkflows); the explicit refresh() below is a third call whose
      // probeMount alone flips the outcome (401 short-circuits before a
      // second getWorkflows call is ever made).
      transport.onSequence('GET', '/workflows', [
        (status: 200, body: ['a']),
        (status: 200, body: ['a']),
        (status: 401, body: {'error': 'unauthorized'}),
      ]);
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();
      expect(
        container.read(engineWorkflowsProvider),
        isA<EngineWorkflowsLoaded>(),
      );

      await container.read(engineWorkflowsProvider.notifier).refresh();
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsUnavailable>());
      expect(
        (state as EngineWorkflowsUnavailable).status,
        EngineStatus.unauthorized,
      );
    });

    test('a fetch failure after an available probe degrades to unreachable, '
        'never crashes', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      transport.onSequence('GET', '/workflows', [
        (status: 200, body: ['a']), // probeMount succeeds
        (status: 500, body: 'internal error'), // getWorkflows fails
      ]);
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      final state = container.read(engineWorkflowsProvider);
      expect(state, isA<EngineWorkflowsUnavailable>());
      expect(
        (state as EngineWorkflowsUnavailable).status,
        EngineStatus.unreachable,
      );
    });

    test('a sentinel engine key never appears in any produced state', () async {
      storage.store['bastion.auth.engine_key'] = _sentinelKey;
      transport.onSequence('GET', '/workflows', [
        (status: 200, body: ['a']),
        (status: 500, body: 'internal error'),
      ]);
      container = await _makeReadyContainer(
        storage: storage,
        transport: transport,
      );
      container.read(engineWorkflowsProvider); // trigger construction
      await pump();

      // Sending the key as the `X-API-Key` header is the whole point of
      // authenticating — Rule 7 is about it never leaking into a STATE,
      // error message, or log line, not that it's never transmitted, so
      // this deliberately does not assert against `transport.calls`
      // headers.
      final state = container.read(engineWorkflowsProvider);
      expect(state.toString(), isNot(contains(_sentinelKey)));
      if (state is EngineWorkflowsUnavailable) {
        expect(state.error ?? '', isNot(contains(_sentinelKey)));
      }
    });
  });
}
