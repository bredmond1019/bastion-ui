// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

// ---------------------------------------------------------------------------
// Fake transport (no real network)
// ---------------------------------------------------------------------------

/// A recorded request made against [FakeHttpTransport].
typedef RecordedCall = ({
  String method,
  String url,
  Map<String, String> headers,
  String? body,
});

/// Stub [HttpTransport] for unit tests.
///
/// Pre-programme responses with [setResponse]; each request consumes the
/// first queued entry (FIFO), regardless of HTTP method. Records every call
/// (method, url, headers, body) in [calls].
final class FakeHttpTransport implements HttpTransport {
  final List<RecordedCall> calls = [];
  final List<({int statusCode, String body})> _responses = [];

  void setResponse({required int statusCode, required Object body}) {
    final encoded = body is String ? body : jsonEncode(body);
    _responses.add((statusCode: statusCode, body: encoded));
  }

  ({int statusCode, String body}) _consume(String method, String url) {
    if (_responses.isEmpty) {
      throw StateError(
        'FakeHttpTransport: no response queued for $method $url',
      );
    }
    return _responses.removeAt(0);
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'GET', url: url, headers: headers, body: null));
    return _consume('GET', url);
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add((method: 'POST', url: url, headers: headers, body: body));
    return _consume('POST', url);
  }

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'DELETE', url: url, headers: headers, body: null));
    return _consume('DELETE', url);
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

  group('BastionApi.getSessions', () {
    test('returns SessionDto list on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: [
          {'name': 'main', 'state': 'running', 'last_line': '\$ cargo test'},
          {'name': 'scratch', 'state': 'idle', 'last_line': ''},
        ],
      );
      final api = makeApi(t);

      final sessions = await api.getSessions();

      expect(sessions, hasLength(2));
      expect(sessions[0].name, 'main');
      expect(sessions[0].state, 'running');
      expect(sessions[1].name, 'scratch');
      expect(sessions[1].state, 'idle');
    });

    test('returns empty list for an empty tmux server', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 200, body: []);
      final api = makeApi(t);

      final sessions = await api.getSessions();

      expect(sessions, isEmpty);
    });

    test('hits GET /api/sessions', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 200, body: []);
      final api = makeApi(t);
      await api.getSessions();

      expect(t.calls.single.method, 'GET');
      expect(t.calls.single.url, 'http://127.0.0.1:4317/api/sessions');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on tmux degradation (503)', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 503,
        body: {'code': 'C001', 'message': 'no tmux server running'},
      );
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<ApiError>()));
    });

    test('throws ApiError when the body is not a JSON array', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 200, body: {'not': 'a list'});
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.getPane', () {
    test('returns PaneDto on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'session_name': 'main',
          'lines': ['line1', 'line2'],
        },
      );
      final api = makeApi(t);

      final pane = await api.getPane('main');

      expect(pane.sessionName, 'main');
      expect(pane.lines, ['line1', 'line2']);
    });

    test('hits GET /api/sessions/{name}/pane without lines param', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'session_name': 'main', 'lines': []},
      );
      final api = makeApi(t);
      await api.getPane('main');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/sessions/main/pane',
      );
    });

    test('appends ?lines=N when lines is given', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'session_name': 'main', 'lines': []},
      );
      final api = makeApi(t);
      await api.getPane('main', lines: 20);

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/sessions/main/pane?lines=20',
      );
    });

    test('URL-encodes the session name', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'session_name': 'my session', 'lines': []},
      );
      final api = makeApi(t);
      await api.getPane('my session');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/sessions/my%20session/pane',
      );
    });

    test('throws ApiError on 404 when the session does not exist', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 404,
        body: {'code': 'C002', 'message': "session not found"},
      );
      final api = makeApi(t);

      await expectLater(api.getPane('nosuch'), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.sendKeys', () {
    test('POSTs keys and returns normally on 204', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 204, body: '');
      final api = makeApi(t);

      await api.sendKeys('main', 'cargo test');

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions/main/send');
      expect(call.body, jsonEncode({'keys': 'cargo test'}));
      expect(call.headers['Content-Type'], 'application/json');
      expect(call.headers['Authorization'], 'Bearer test-token');
    });

    test('throws ApiError on 404', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 404,
        body: {'code': 'C002', 'message': 'session not found'},
      );
      final api = makeApi(t);

      await expectLater(api.sendKeys('nosuch', 'x'), throwsA(isA<ApiError>()));
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.sendKeys('main', 'x'),
        throwsA(isA<FatalAuthError>()),
      );
    });
  });

  group('BastionApi.sendKey', () {
    test('POSTs a named key and returns normally on 204', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 204, body: '');
      final api = makeApi(t);

      await api.sendKey('main', 'Escape');

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions/main/key');
      expect(call.body, jsonEncode({'key': 'Escape'}));
    });

    test('throws ApiError on 404', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 404,
        body: {'code': 'C002', 'message': 'session not found'},
      );
      final api = makeApi(t);

      await expectLater(
        api.sendKey('nosuch', 'Escape'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('BastionApi.createSession', () {
    test('POSTs name only and returns normally on 201', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 201, body: '');
      final api = makeApi(t);

      await api.createSession('mysession');

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions');
      expect(call.body, jsonEncode({'name': 'mysession'}));
    });

    test('POSTs name and dir when dir is given', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 201, body: '');
      final api = makeApi(t);

      await api.createSession('mysession', dir: '/home/user/project');

      expect(
        t.calls.single.body,
        jsonEncode({'name': 'mysession', 'dir': '/home/user/project'}),
      );
    });

    test('throws ApiError on 500 when the name is already in use', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 500, body: 'name in use');
      final api = makeApi(t);

      await expectLater(
        api.createSession('mysession'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('BastionApi.deleteSession', () {
    test('DELETEs the session and returns normally on 204', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 204, body: '');
      final api = makeApi(t);

      await api.deleteSession('mysession');

      final call = t.calls.single;
      expect(call.method, 'DELETE');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions/mysession');
    });

    test('URL-encodes the session name', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 204, body: '');
      final api = makeApi(t);

      await api.deleteSession('my session');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/sessions/my%20session',
      );
    });

    test('throws ApiError on 404 when the session does not exist', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 404,
        body: {'code': 'C002', 'message': 'session not found'},
      );
      final api = makeApi(t);

      await expectLater(api.deleteSession('nosuch'), throwsA(isA<ApiError>()));
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.deleteSession('main'),
        throwsA(isA<FatalAuthError>()),
      );
    });
  });
}
