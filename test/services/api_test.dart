// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/models/dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import '../support/fake_http_transport.dart';

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
      t.on(
        'GET',
        '/health',

        status: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);

      final health = await api.getHealth();

      expect(health.status, 'ok');
      expect(health.service, 'bastion');
    });

    test('hits the correct URL', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/health',

        status: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);
      await api.getHealth();

      expect(t.calls.single.url, 'http://127.0.0.1:4317/health');
    });

    test('sends Authorization header on /health', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/health',

        status: 200,
        body: {'status': 'ok', 'service': 'bastion'},
      );
      final api = makeApi(t);
      await api.getHealth();

      expect(t.calls.single.headers['Authorization'], 'Bearer test-token');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/health',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<FatalAuthError>()));
    });

    test('FatalAuthError carries parsed ErrorPayload', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/health',

        status: 401,
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
      t.on('GET', '/health', status: 401, body: 'not json');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on non-401 HTTP error', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/health', status: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<ApiError>()));
    });

    test('ApiError carries status code', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/health', status: 503, body: 'unavailable');
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
      t.on('GET', '/health', status: 200, body: 'not-json!!');
      final api = makeApi(t);

      await expectLater(api.getHealth(), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi base URL construction', () {
    test('constructs correct base URL from host and port', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/health',

        status: 200,
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
      t.on(
        'GET',
        '/api/sessions',

        status: 200,
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
      t.on('GET', '/api/sessions', status: 200, body: []);
      final api = makeApi(t);

      final sessions = await api.getSessions();

      expect(sessions, isEmpty);
    });

    test('hits GET /api/sessions', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/sessions', status: 200, body: []);
      final api = makeApi(t);
      await api.getSessions();

      expect(t.calls.single.method, 'GET');
      expect(t.calls.single.url, 'http://127.0.0.1:4317/api/sessions');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/sessions',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on tmux degradation (503)', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/sessions',

        status: 503,
        body: {'code': 'C001', 'message': 'no tmux server running'},
      );
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<ApiError>()));
    });

    test('throws ApiError when the body is not a JSON array', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/sessions', status: 200, body: {'not': 'a list'});
      final api = makeApi(t);

      await expectLater(api.getSessions(), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.getPane', () {
    test('returns PaneDto on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/sessions/main/pane',

        status: 200,
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
      t.on(
        'GET',
        '/api/sessions/main/pane',

        status: 200,
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
      t.on(
        'GET',
        '/api/sessions/main/pane',

        status: 200,
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
      t.on(
        'GET',
        '/api/sessions/my%20session/pane',

        status: 200,
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
      t.on(
        'GET',
        '/api/sessions/nosuch/pane',

        status: 404,
        body: {'code': 'C002', 'message': "session not found"},
      );
      final api = makeApi(t);

      await expectLater(api.getPane('nosuch'), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.sendKeys', () {
    test('POSTs keys and returns normally on 204', () async {
      final t = FakeHttpTransport();
      t.on('POST', '/api/sessions/main/send', status: 204, body: '');
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
      t.on(
        'POST',
        '/api/sessions/nosuch/send',

        status: 404,
        body: {'code': 'C002', 'message': 'session not found'},
      );
      final api = makeApi(t);

      await expectLater(api.sendKeys('nosuch', 'x'), throwsA(isA<ApiError>()));
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/api/sessions/main/send',

        status: 401,
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
      t.on('POST', '/api/sessions/main/key', status: 204, body: '');
      final api = makeApi(t);

      await api.sendKey('main', 'Escape');

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions/main/key');
      expect(call.body, jsonEncode({'key': 'Escape'}));
    });

    test('throws ApiError on 404', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/api/sessions/nosuch/key',

        status: 404,
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
      t.on('POST', '/api/sessions', status: 201, body: '');
      final api = makeApi(t);

      await api.createSession('mysession');

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions');
      expect(call.body, jsonEncode({'name': 'mysession'}));
    });

    test('POSTs name and dir when dir is given', () async {
      final t = FakeHttpTransport();
      t.on('POST', '/api/sessions', status: 201, body: '');
      final api = makeApi(t);

      await api.createSession('mysession', dir: '/home/user/project');

      expect(
        t.calls.single.body,
        jsonEncode({'name': 'mysession', 'dir': '/home/user/project'}),
      );
    });

    test('throws ApiError on 500 when the name is already in use', () async {
      final t = FakeHttpTransport();
      t.on('POST', '/api/sessions', status: 500, body: 'name in use');
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
      t.on('DELETE', '/api/sessions/mysession', status: 204, body: '');
      final api = makeApi(t);

      await api.deleteSession('mysession');

      final call = t.calls.single;
      expect(call.method, 'DELETE');
      expect(call.url, 'http://127.0.0.1:4317/api/sessions/mysession');
    });

    test('URL-encodes the session name', () async {
      final t = FakeHttpTransport();
      t.on('DELETE', '/api/sessions/my%20session', status: 204, body: '');
      final api = makeApi(t);

      await api.deleteSession('my session');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/sessions/my%20session',
      );
    });

    test('throws ApiError on 404 when the session does not exist', () async {
      final t = FakeHttpTransport();
      t.on(
        'DELETE',
        '/api/sessions/nosuch',

        status: 404,
        body: {'code': 'C002', 'message': 'session not found'},
      );
      final api = makeApi(t);

      await expectLater(api.deleteSession('nosuch'), throwsA(isA<ApiError>()));
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'DELETE',
        '/api/sessions/main',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.deleteSession('main'),
        throwsA(isA<FatalAuthError>()),
      );
    });
  });

  group('BastionApi.getRepos', () {
    test('returns RepoSummaryDto list on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos',

        status: 200,
        body: [
          {
            'name': 'bastion-ui',
            'now': 'wiring dashboard',
            'has_handoff': true,
          },
          {'name': 'bastion', 'now': 'serve-api v0.3', 'has_handoff': false},
        ],
      );
      final api = makeApi(t);

      final repos = await api.getRepos();

      expect(repos, hasLength(2));
      expect(repos[0].name, 'bastion-ui');
      expect(repos[0].now, 'wiring dashboard');
      expect(repos[0].hasHandoff, isTrue);
      expect(repos[1].name, 'bastion');
      expect(repos[1].hasHandoff, isFalse);
    });

    test('hits GET /api/repos', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 200, body: []);
      final api = makeApi(t);
      await api.getRepos();

      expect(t.calls.single.method, 'GET');
      expect(t.calls.single.url, 'http://127.0.0.1:4317/api/repos');
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(api.getRepos(), throwsA(isA<FatalAuthError>()));
    });

    test('throws ApiError on non-2xx HTTP error', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 500, body: 'internal server error');
      final api = makeApi(t);

      await expectLater(api.getRepos(), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.getRepoStatus', () {
    test('returns RepoStatusDto on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/status',

        status: 200,
        body: {
          'name': 'bastion-ui',
          'now': 'wiring dashboard',
          'next': 'repo detail',
          'blocked': '',
          'has_handoff': true,
          'momentum_now': 'a',
          'momentum_next': 'b',
          'momentum_blocked': 'c',
          'momentum_improve': 'd',
          'momentum_recurring': 'e',
        },
      );
      final api = makeApi(t);

      final status = await api.getRepoStatus('bastion-ui');

      expect(status.name, 'bastion-ui');
      expect(status.now, 'wiring dashboard');
      expect(status.next, 'repo detail');
      expect(status.hasHandoff, isTrue);
      expect(status.momentumNow, 'a');
    });

    test('hits GET /api/repos/{name}/status with URL-encoded name', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/my%20repo/status',

        status: 200,
        body: {
          'name': 'my repo',
          'now': '',
          'next': '',
          'blocked': '',
          'has_handoff': false,
          'momentum_now': '',
          'momentum_next': '',
          'momentum_blocked': '',
          'momentum_improve': '',
          'momentum_recurring': '',
        },
      );
      final api = makeApi(t);
      await api.getRepoStatus('my repo');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/repos/my%20repo/status',
      );
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/status',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoStatus('bastion-ui'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('throws ApiError on 404 when the repo does not exist', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/nosuch/status',

        status: 404,
        body: {'code': 'C002', 'message': 'repo not found'},
      );
      final api = makeApi(t);

      await expectLater(api.getRepoStatus('nosuch'), throwsA(isA<ApiError>()));
    });
  });

  group('BastionApi.getRepoHandoff', () {
    test('returns HandoffInfo on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',

        status: 200,
        body: {'title': 'Handoff — BU.1.A', 'body': '## Summary\n...'},
      );
      final api = makeApi(t);

      final handoff = await api.getRepoHandoff('bastion-ui');

      expect(handoff, isNotNull);
      expect(handoff!.title, 'Handoff — BU.1.A');
      expect(handoff.body, '## Summary\n...');
    });

    test('hits GET /api/repos/{name}/handoff', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',
        status: 200,
        body: {'title': 't', 'body': 'b'},
      );
      final api = makeApi(t);
      await api.getRepoHandoff('bastion-ui');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/repos/bastion-ui/handoff',
      );
    });

    test('returns null on 404 with code C002 (no handoff.md)', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',

        status: 404,
        body: {'code': 'C002', 'message': 'no handoff.md'},
      );
      final api = makeApi(t);

      final handoff = await api.getRepoHandoff('bastion-ui');

      expect(handoff, isNull);
    });

    test('throws ApiError on 404 with a different/no code', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',

        status: 404,
        body: {'code': 'C999', 'message': 'something else'},
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoHandoff('bastion-ui'),
        throwsA(isA<ApiError>()),
      );
    });

    test('throws ApiError on 404 with non-JSON body', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',
        status: 404,
        body: 'not json',
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoHandoff('bastion-ui'),
        throwsA(isA<ApiError>()),
      );
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/handoff',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoHandoff('bastion-ui'),
        throwsA(isA<FatalAuthError>()),
      );
    });
  });

  group('BastionApi.getRepoWorkflows', () {
    test('returns WorkflowStateDto list on 200 with correct JSON', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/workflows',

        status: 200,
        body: [
          {
            'spec_slug': '2.A-dashboard-repo-detail',
            'branch': '2.A-dashboard-repo-detail-flow',
            'status': 'running',
            'current_task': 2,
            'started_at': '2026-07-02T10:00:00Z',
            'updated_at': '2026-07-02T10:15:00Z',
          },
        ],
      );
      final api = makeApi(t);

      final workflows = await api.getRepoWorkflows('bastion-ui');

      expect(workflows, hasLength(1));
      expect(workflows[0].specSlug, '2.A-dashboard-repo-detail');
      expect(workflows[0].status, 'running');
      expect(workflows[0].currentTask, 2);
    });

    test('hits GET /api/repos/{name}/workflows', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos/bastion-ui/workflows', status: 200, body: []);
      final api = makeApi(t);
      await api.getRepoWorkflows('bastion-ui');

      expect(
        t.calls.single.url,
        'http://127.0.0.1:4317/api/repos/bastion-ui/workflows',
      );
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/workflows',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoWorkflows('bastion-ui'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('throws ApiError on non-2xx HTTP error', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/api/repos/bastion-ui/workflows',
        status: 500,
        body: 'internal server error',
      );
      final api = makeApi(t);

      await expectLater(
        api.getRepoWorkflows('bastion-ui'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('BastionApi.postCommand', () {
    test('POSTs an inject request and returns the target session id', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/api/actions/command',
        status: 200,
        body: {'session': 'main'},
      );
      final api = makeApi(t);

      final session = await api.postCommand(
        const CommandRequest(
          mode: CommandMode.inject,
          session: 'main',
          command: '/status',
        ),
      );

      expect(session, 'main');
      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/api/actions/command');
      expect(
        call.body,
        jsonEncode({'mode': 'inject', 'session': 'main', 'command': '/status'}),
      );
      expect(call.headers['Content-Type'], 'application/json');
      expect(call.headers['Authorization'], 'Bearer test-token');
    });

    test('POSTs a spawn request and returns the target session id', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/api/actions/command',
        status: 200,
        body: {'session': 'work'},
      );
      final api = makeApi(t);

      final session = await api.postCommand(
        const CommandRequest(
          mode: CommandMode.spawn,
          name: 'work',
          dir: '/repo',
          model: CommandModel.opus,
          command: '/status',
        ),
      );

      expect(session, 'work');
      final call = t.calls.single;
      expect(
        call.body,
        jsonEncode({
          'mode': 'spawn',
          'name': 'work',
          'dir': '/repo',
          'model': 'opus',
          'command': '/status',
        }),
      );
    });

    test('throws FatalAuthError on 401', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/api/actions/command',

        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final api = makeApi(t);

      await expectLater(
        api.postCommand(
          const CommandRequest(
            mode: CommandMode.inject,
            session: 'main',
            command: '/status',
          ),
        ),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test(
      'throws ApiError with statusCode 400 on bad mode/field combo',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/api/actions/command',

          status: 400,
          body: {'code': 'C006', 'message': 'invalid request'},
        );
        final api = makeApi(t);

        try {
          await api.postCommand(
            const CommandRequest(
              mode: CommandMode.inject,
              session: 'main',
              command: '/status',
            ),
          );
          fail('expected ApiError');
        } on ApiError catch (e) {
          expect(e.statusCode, 400);
        }
      },
    );

    test(
      'throws ApiError with statusCode 404 on inject into unknown session',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/api/actions/command',

          status: 404,
          body: {'code': 'C002', 'message': 'session not found'},
        );
        final api = makeApi(t);

        try {
          await api.postCommand(
            const CommandRequest(
              mode: CommandMode.inject,
              session: 'nosuch',
              command: '/status',
            ),
          );
          fail('expected ApiError');
        } on ApiError catch (e) {
          expect(e.statusCode, 404);
        }
      },
    );

    test(
      'throws ApiError with statusCode 504 on spawn readiness timeout',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/api/actions/command',

          status: 504,
          body: {'code': 'C007', 'message': 'spawn readiness timeout'},
        );
        final api = makeApi(t);

        try {
          await api.postCommand(
            const CommandRequest(
              mode: CommandMode.spawn,
              name: 'work',
              command: '/status',
            ),
          );
          fail('expected ApiError');
        } on ApiError catch (e) {
          expect(e.statusCode, 504);
        }
      },
    );
  });
}
