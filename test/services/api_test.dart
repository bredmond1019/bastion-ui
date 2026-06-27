// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

// ---------------------------------------------------------------------------
// Fake transport (no real network)
// ---------------------------------------------------------------------------

/// Stub [HttpTransport] for unit tests.
///
/// Pre-programme responses with [setResponse]; each [get] call consumes the
/// first queued entry (FIFO). Records every [get] call in [calls].
final class FakeHttpTransport implements HttpTransport {
  final List<({String url, Map<String, String> headers})> calls = [];
  final List<({int statusCode, String body})> _responses = [];

  void setResponse({required int statusCode, required Object body}) {
    final encoded = body is String ? body : jsonEncode(body);
    _responses.add((statusCode: statusCode, body: encoded));
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((url: url, headers: headers));
    if (_responses.isEmpty) {
      throw StateError('FakeHttpTransport: no response queued for GET $url');
    }
    return _responses.removeAt(0);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BastionApi makeApi(FakeHttpTransport transport) => BastionApi(
  host: '127.0.0.1',
  port: 4317,
  token: 'test-token',
  transport: transport,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BastionApi.getHealth', () {
    test('returns HealthDto on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);

      final health = await api.getHealth();

      expect(health.status, 'ok');
      expect(health.service, 'bastion');
    });

    test('hits the correct URL', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);
      await api.getHealth();

      expect(t.calls.single.url, 'http://127.0.0.1:4317/health');
    });

    test('sends Authorization header on /health', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);
      await api.getHealth();

      expect(t.calls.single.headers['Authorization'], 'Bearer test-token');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<FatalAuthError>()));
    });

    test('FatalAuthError carries parsed ErrorPayload', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      try {
        await api.getHealth();
        fail('expected FatalAuthError');
      } on FatalAuthError catch (e) {
        expect(e.payload.code, 'unauthorized');
        expect(e.payload.error, 'unauthorized');
      }
    });

    test('throws FatalAuthError on 401 with non-JSON body', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 401, body: 'not json');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on non-401 HTTP error', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<ApiError>()));
    });

    test('ApiError carries status code', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 503, body: 'unavailable');
      final api = makeApi(t);

      try {
        await api.getHealth();
        fail('expected ApiError');
      } on ApiError catch (e) {
        expect(e.statusCode, 503);
      }
    });

    test('throws ApiError on 200 with invalid JSON', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 200, body: 'not-json!!');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi base URL construction', () {
    test('constructs correct base URL from host and port', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = BastionApi(
        host: '100.64.0.1',
        port: 4317,
        token: 'tok',
        transport: t,
      );
      await api.getHealth();

      expect(t.calls.single.url, startsWith('http://100.64.0.1:4317'));
    });
  });

  group('FatalAuthError and ApiError toString', () {
    test('FatalAuthError.toString contains code', () {
      final err = FatalAuthError(
        const ErrorPayload(code: 'unauthorized', error: 'unauthorized'),
      );
      expect(err.toString(), contains('unauthorized'));
    });

    test('ApiError.toString contains status code', () {
      const err = ApiError(statusCode: 404, body: 'not found');
      expect(err.toString(), contains('404'));
    });
  });
}
