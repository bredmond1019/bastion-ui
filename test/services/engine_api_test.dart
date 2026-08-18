// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/bastion_api.dart'
    show ApiError, FatalAuthError, HttpTransport;
import 'package:bastion_ui/services/engine_api.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _sentinelKey = 'sentinel-engine-key-do-not-leak-8f2c1e';

EngineApi makeEngine(
  FakeHttpTransport transport, {
  String? key = _sentinelKey,
}) => EngineApi(host: '127.0.0.1', port: 4317, key: key, transport: transport);

/// A transport whose GET always throws a [SocketException], simulating an
/// unreachable server — the fake router has no built-in way to model a
/// socket-level failure, so this is a small purpose-built stand-in.
class _UnreachableTransport implements HttpTransport {
  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) => throw const SocketException('connection refused');

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => throw const SocketException('connection refused');

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) => throw const SocketException('connection refused');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EngineApi.getWorkflows', () {
    test('hits the server root with no /api prefix', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 200, body: ['b', 'a']);
      final engine = makeEngine(t);

      await engine.getWorkflows();

      expect(t.calls.single.url, 'http://127.0.0.1:4317/workflows');
      expect(t.calls.single.url.contains('/api'), isFalse);
    });

    test('sends X-API-Key and no Authorization header', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 200, body: ['a']);
      final engine = makeEngine(t);

      await engine.getWorkflows();

      expect(t.calls.single.headers['X-API-Key'], _sentinelKey);
      expect(t.calls.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a 200 registry parses to a sorted List<String>', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 200, body: ['zeta', 'alpha', 'mid']);
      final engine = makeEngine(t);

      final types = await engine.getWorkflows();

      expect(types, ['alpha', 'mid', 'zeta']);
    });

    test('401 surfaces as FatalAuthError, not a crash', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/workflows',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(engine.getWorkflows(), throwsA(isA<FatalAuthError>()));
    });

    test('a null key short-circuits to EngineNotConfiguredError with zero '
        'requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.getWorkflows(),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });

    test('an empty-string key short-circuits to EngineNotConfiguredError '
        'with zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: '');

      await expectLater(
        engine.getWorkflows(),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('EngineApi.getWorkflowGraph', () {
    test('an unknown type surfaces 404 distinctly as ApiError', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/workflows/nonexistent/graph',
        status: 404,
        body: {'error': 'not found'},
      );
      final engine = makeEngine(t);

      await expectLater(
        engine.getWorkflowGraph('nonexistent'),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('hits the correctly-shaped URL for a known type', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows/deploy/graph', status: 200, body: {'nodes': []});
      final engine = makeEngine(t);

      await engine.getWorkflowGraph('deploy');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/workflows/deploy/graph',
      );
    });
  });

  group('EngineApi.probeMount', () {
    test('notConfigured when no key is held, with zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      final status = await engine.probeMount();

      expect(status, EngineStatus.notConfigured);
      expect(t.calls, isEmpty);
    });

    test('notMounted on a 404 response', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 404, body: 'not found');
      final engine = makeEngine(t);

      expect(await engine.probeMount(), EngineStatus.notMounted);
    });

    test('notMounted on a 405 response', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 405, body: 'method not allowed');
      final engine = makeEngine(t);

      expect(await engine.probeMount(), EngineStatus.notMounted);
    });

    test('unauthorized on a 401 response', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/workflows',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      expect(await engine.probeMount(), EngineStatus.unauthorized);
    });

    test('available on a 200 response', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/workflows', status: 200, body: ['a']);
      final engine = makeEngine(t);

      expect(await engine.probeMount(), EngineStatus.available);
    });

    test('unreachable on a SocketException', () async {
      final engine = EngineApi(
        host: '127.0.0.1',
        port: 4317,
        key: _sentinelKey,
        transport: _UnreachableTransport(),
      );

      expect(await engine.probeMount(), EngineStatus.unreachable);
    });
  });

  group('leak assertion (Standing Rule 7)', () {
    test(
      'the sentinel key appears nowhere in a 401 error toString()',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'GET',
          '/workflows',
          status: 401,
          body: {'error': 'unauthorized', 'code': 'unauthorized'},
        );
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.getWorkflows();
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );

    test(
      'the sentinel key appears nowhere in a 500 error toString()',
      () async {
        final t = FakeHttpTransport();
        t.on('GET', '/workflows', status: 500, body: 'internal error');
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.getWorkflows();
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );
  });
}
