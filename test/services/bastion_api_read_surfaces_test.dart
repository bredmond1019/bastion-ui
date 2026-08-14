// ignore_for_file: avoid_relative_lib_imports
//
// Tests for the four v0.30 read surfaces added to [BastionApi]:
// getBoard, getAttention, getDocsTree, getDocsFile (serve-api.md §13/§15/§16).
//
// Reuses the FakeHttpTransport pattern from test/services/api_test.dart —
// see that file for the canonical shape; this file keeps its own private
// copy to stay self-contained and independently runnable.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/bastion_api.dart';

// ---------------------------------------------------------------------------
// Fake transport (no real network)
// ---------------------------------------------------------------------------

typedef RecordedCall = ({
  String method,
  String url,
  Map<String, String> headers,
  String? body,
});

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

const _unauthorizedBody = {'error': 'unauthorized', 'code': 'unauthorized'};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BastionApi.getBoard', () {
    test(
      'hits GET /api/board with no query params when none supplied',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(
          statusCode: 200,
          body: {'lanes': {}, 'repos': [], 'stale': false},
        );
        final api = makeApi(t);

        await api.getBoard();

        expect(t.calls.single.method, 'GET');
        expect(t.calls.single.url, 'http://127.0.0.1:4317/api/board');
      },
    );

    test('emits only the supplied query params, correctly encoded', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'lanes': {}, 'repos': [], 'stale': false},
      );
      final api = makeApi(t);

      await api.getBoard(scope: 'tier', tier: 'core apps');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/board?scope=tier&tier=core+apps',
      );
    });

    test('graph: false (the default) never emits ?graph=1', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'lanes': {}, 'repos': [], 'stale': false},
      );
      final api = makeApi(t);

      await api.getBoard(scope: 'hq');

      expect(t.calls.single.url, isNot(contains('graph')));
    });

    test('graph: true emits ?graph=1', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'lanes': {}, 'repos': [], 'stale': false},
      );
      final api = makeApi(t);

      await api.getBoard(scope: 'hq', graph: true);

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/board?scope=hq&graph=1',
      );
    });

    test('decodes a full BoardDto payload', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'scope': 'hq',
          'lanes': {
            'now': [
              {
                'id': 'BA.11.K',
                'title': 'Cross-brain board read endpoint',
                'repo': 'bastion',
                'status': 'in_progress',
                'blocked_by': [],
                'epics': ['bastion-surfaces'],
                'wave': 3,
              },
            ],
          },
          'repos': [],
          'stale': false,
        },
      );
      final api = makeApi(t);

      final board = await api.getBoard(scope: 'hq');

      expect(board.scope, 'hq');
      expect(board.lanes.now, hasLength(1));
      expect(board.lanes.now.single.id, 'BA.11.K');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 401, body: _unauthorizedBody);
      final api = makeApi(t);

      await expectLater(api.getBoard(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on 500', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(api.getBoard(), throwsA(isA<ApiError>()));
    });

    test(
      'throws ApiError (not a silent empty object) on malformed body',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(statusCode: 200, body: 'not-json!!');
        final api = makeApi(t);

        await expectLater(api.getBoard(), throwsA(isA<ApiError>()));
      },
    );
  });

  group('BastionApi.getAttention', () {
    test(
      'hits GET /api/attention with no query params when none supplied',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(
          statusCode: 200,
          body: {
            'as_of': '2026-08-14',
            'lanes': {},
            'thresholds': {
              'env_days': 7,
              'deferred_days': 14,
              'known_issue_days': 30,
              'constraint_days': 30,
              'backlog_days': 21,
            },
          },
        );
        final api = makeApi(t);

        await api.getAttention();

        expect(t.calls.single.url, 'http://127.0.0.1:4317/api/attention');
      },
    );

    test('emits only the supplied query params, correctly encoded', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'as_of': '2026-08-14',
          'lanes': {},
          'thresholds': {
            'env_days': 7,
            'deferred_days': 14,
            'known_issue_days': 30,
            'constraint_days': 30,
            'backlog_days': 21,
          },
        },
      );
      final api = makeApi(t);

      await api.getAttention(scope: 'tier', tier: 'core apps');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/attention?scope=tier&tier=core+apps',
      );
    });

    test('decodes a full AttentionDto payload', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'scope': 'hq',
          'as_of': '2026-08-14',
          'lanes': {
            'stale_carryover': [
              {
                'repo': 'bastion-ui',
                'slug': 'x',
                'kind': 'env',
                'text': 'stale env note',
                'threshold_days': 7,
                'lane': 'aging',
                'clears_when_satisfied': false,
              },
            ],
          },
          'thresholds': {
            'env_days': 7,
            'deferred_days': 14,
            'known_issue_days': 30,
            'constraint_days': 30,
            'backlog_days': 21,
          },
        },
      );
      final api = makeApi(t);

      final attention = await api.getAttention(scope: 'hq');

      expect(attention.asOf, '2026-08-14');
      expect(attention.lanes.staleCarryover, hasLength(1));
      expect(attention.lanes.staleCarryover.single.ageDays, isNull);
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 401, body: _unauthorizedBody);
      final api = makeApi(t);

      await expectLater(api.getAttention(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on 500', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(api.getAttention(), throwsA(isA<ApiError>()));
    });

    test(
      'throws ApiError (not a silent empty object) on malformed body',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(statusCode: 200, body: 'not-json!!');
        final api = makeApi(t);

        await expectLater(api.getAttention(), throwsA(isA<ApiError>()));
      },
    );
  });

  group('BastionApi.getDocsTree', () {
    test('hits GET /api/docs/{repo}/tree with URL-encoded repo', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'repo': 'bastion ui', 'root': '', 'entries': []},
      );
      final api = makeApi(t);

      await api.getDocsTree('bastion ui');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/docs/bastion%20ui/tree',
      );
    });

    test('appends ?path=<encoded> when path is given', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'repo': 'bastion-ui', 'root': 'docs', 'entries': []},
      );
      final api = makeApi(t);

      await api.getDocsTree('bastion-ui', path: 'docs/sub dir');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/docs/bastion-ui/tree?path=docs%2Fsub+dir',
      );
    });

    test('decodes a full DocTreeDto payload', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'repo': 'bastion-ui',
          'root': '',
          'entries': [
            {'path': 'docs', 'name': 'docs', 'is_dir': true},
            {'path': 'docs/api.md', 'name': 'api.md', 'is_dir': false},
          ],
        },
      );
      final api = makeApi(t);

      final tree = await api.getDocsTree('bastion-ui');

      expect(tree.entries, hasLength(2));
      expect(tree.entries[0].isDir, isTrue);
      expect(tree.entries[1].isDir, isFalse);
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 401, body: _unauthorizedBody);
      final api = makeApi(t);

      await expectLater(
        api.getDocsTree('bastion-ui'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('throws ApiError on 500', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(
        api.getDocsTree('bastion-ui'),
        throwsA(isA<ApiError>()),
      );
    });

    test(
      'throws ApiError (not a silent empty object) on malformed body',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(statusCode: 200, body: 'not-json!!');
        final api = makeApi(t);

        await expectLater(
          api.getDocsTree('bastion-ui'),
          throwsA(isA<ApiError>()),
        );
      },
    );
  });

  group('BastionApi.getDocsFile', () {
    test('hits GET /api/docs/{repo}/file?path=<encoded>', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'repo': 'bastion-ui',
          'path': 'docs/api.md',
          'content': '# API',
          'bytes': 5,
        },
      );
      final api = makeApi(t);

      await api.getDocsFile('bastion-ui', path: 'docs/api.md');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/docs/bastion-ui/file?path=docs%2Fapi.md',
      );
    });

    test('URL-encodes the repo segment', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {'repo': 'my repo', 'path': 'a.md', 'content': '', 'bytes': 0},
      );
      final api = makeApi(t);

      await api.getDocsFile('my repo', path: 'a.md');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/docs/my%20repo/file?path=a.md',
      );
    });

    test('decodes a full DocFileDto payload', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 200,
        body: {
          'repo': 'bastion-ui',
          'path': 'docs/api.md',
          'content': '# API\n',
          'bytes': 6,
          'modified': '2026-08-14T00:00:00Z',
        },
      );
      final api = makeApi(t);

      final file = await api.getDocsFile('bastion-ui', path: 'docs/api.md');

      expect(file.content, '# API\n');
      expect(file.modified, '2026-08-14T00:00:00Z');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.setResponse(statusCode: 401, body: _unauthorizedBody);
      final api = makeApi(t);

      await expectLater(
        api.getDocsFile('bastion-ui', path: 'a.md'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('throws ApiError on a rejected traversal path (400)', () async {
      final t = FakeHttpTransport();
      t.setResponse(
        statusCode: 400,
        body: {'code': 'C006', 'message': 'path traversal rejected'},
      );
      final api = makeApi(t);

      await expectLater(
        api.getDocsFile('bastion-ui', path: '../../etc/passwd'),
        throwsA(isA<ApiError>()),
      );
    });

    test(
      'throws ApiError (not a silent empty object) on malformed body',
      () async {
        final t = FakeHttpTransport();
        t.setResponse(statusCode: 200, body: 'not-json!!');
        final api = makeApi(t);

        await expectLater(
          api.getDocsFile('bastion-ui', path: 'a.md'),
          throwsA(isA<ApiError>()),
        );
      },
    );
  });
}
