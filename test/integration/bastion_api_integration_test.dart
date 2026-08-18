// Integration tier for BastionApi (BU.ticket.integration-test-tier task 3).
//
// Untagged by design — these tests must run inside the gating
// `flutter test --exclude-tags e2e` command, not behind a separate
// `integration` tag (see `planning/ticket-integration-test-tier/tasks.md`
// Notes, "On not tagging the tier").
//
// Drives a REAL `BastionApi` against the routing `FakeHttpTransport` (task
// 1) fed with the wire-shaped fixtures (task 2). For every public method
// this asserts: the request path, the query-parameter encoding, the
// `Authorization: Bearer` header, and the decoded return value — plus the
// error contract (401 -> FatalAuthError, non-2xx/non-401 -> ApiError,
// malformed JSON -> ApiError rather than a half-built DTO).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';

import '../support/fake_http_transport.dart';
import '../support/wire_fixtures.dart';

const _host = '127.0.0.1';
const _port = 4317;
const _token = 'test-token-123';
const _baseUrl = 'http://$_host:$_port';

BastionApi _makeApi(FakeHttpTransport transport) =>
    BastionApi(host: _host, port: _port, token: _token, transport: transport);

void _expectBearer(RecordedRequest req) {
  expect(req.headers['Authorization'], 'Bearer $_token');
}

void main() {
  group('getHealth', () {
    test('GET /health — path, bearer header, decoded value', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/health', status: 200, body: healthFixture);
      final api = _makeApi(t);

      final result = await api.getHealth();

      expect(result.status, 'ok');
      expect(result.service, 'bastion');
      final call = t.lastCallTo('GET', '/health')!;
      expect(call.url, '$_baseUrl/health');
      _expectBearer(call);
    });
  });

  group('getSessions', () {
    test('GET /api/sessions — decodes full + minimal entries', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/sessions', status: 200, body: sessionsFixture);
      final api = _makeApi(t);

      final sessions = await api.getSessions();

      expect(sessions, hasLength(2));
      expect(sessions[0].name, 'main');
      expect(sessions[0].lastLine, r'$ cargo test');
      expect(sessions[1].name, 'idle-session');
      expect(sessions[1].lastLine, isNull);
      _expectBearer(t.lastCallTo('GET', '/api/sessions')!);
    });

    test('empty-collection fixture decodes to an empty list', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/sessions', status: 200, body: sessionsEmptyFixture);
      final api = _makeApi(t);

      final sessions = await api.getSessions();

      expect(sessions, isEmpty);
    });
  });

  group('getPane', () {
    test('GET /api/sessions/{name}/pane — no lines param', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/sessions/main/pane',
          status: 200,
          body: paneFullFixture,
        );
      final api = _makeApi(t);

      final pane = await api.getPane('main');

      expect(pane.sessionName, 'main');
      expect(pane.lines, hasLength(3));
      final call = t.lastCallTo('GET', '/api/sessions/main/pane')!;
      expect(call.queryParameters, isEmpty);
      _expectBearer(call);
    });

    test('encodes ?lines= as a query param', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/sessions/main/pane',
          status: 200,
          body: paneFullFixture,
        );
      final api = _makeApi(t);

      await api.getPane('main', lines: 50);

      final call = t.lastCallTo('GET', '/api/sessions/main/pane')!;
      expect(call.queryParameters['lines'], '50');
    });

    test('empty pane fixture decodes to an empty lines list', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/sessions/fresh-session/pane',
          status: 200,
          body: paneEmptyFixture,
        );
      final api = _makeApi(t);

      final pane = await api.getPane('fresh-session');

      expect(pane.lines, isEmpty);
    });

    test(
      'a session name with a slash is percent-encoded in the path',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/sessions/team%2Fmain/pane',
            status: 200,
            body: paneFullFixture,
          );
        final api = _makeApi(t);

        await api.getPane('team/main');

        expect(t.callCount('GET', '/api/sessions/team%2Fmain/pane'), 1);
      },
    );

    test(
      'a session name with a space is percent-encoded in the path',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/sessions/my%20session/pane',
            status: 200,
            body: paneFullFixture,
          );
        final api = _makeApi(t);

        await api.getPane('my session');

        expect(t.callCount('GET', '/api/sessions/my%20session/pane'), 1);
      },
    );
  });

  group('sendKeys', () {
    test('POST /api/sessions/{name}/send — body + headers', () async {
      final t = FakeHttpTransport()
        ..on('POST', '/api/sessions/main/send', status: 204, body: '');
      final api = _makeApi(t);

      await api.sendKeys('main', 'ls -la');

      final call = t.lastCallTo('POST', '/api/sessions/main/send')!;
      expect(call.body, '{"keys":"ls -la"}');
      expect(call.headers['Content-Type'], 'application/json');
      _expectBearer(call);
    });
  });

  group('sendKey', () {
    test('POST /api/sessions/{name}/key — body + headers', () async {
      final t = FakeHttpTransport()
        ..on('POST', '/api/sessions/main/key', status: 204, body: '');
      final api = _makeApi(t);

      await api.sendKey('main', 'C-c');

      final call = t.lastCallTo('POST', '/api/sessions/main/key')!;
      expect(call.body, '{"key":"C-c"}');
      _expectBearer(call);
    });
  });

  group('createSession', () {
    test('POST /api/sessions — with dir', () async {
      final t = FakeHttpTransport()
        ..on('POST', '/api/sessions', status: 201, body: '');
      final api = _makeApi(t);

      await api.createSession('work', dir: '/repo');

      final call = t.lastCallTo('POST', '/api/sessions')!;
      expect(call.body, '{"name":"work","dir":"/repo"}');
      _expectBearer(call);
    });

    test('POST /api/sessions — without dir omits the field', () async {
      final t = FakeHttpTransport()
        ..on('POST', '/api/sessions', status: 201, body: '');
      final api = _makeApi(t);

      await api.createSession('work');

      final call = t.lastCallTo('POST', '/api/sessions')!;
      expect(call.body, '{"name":"work"}');
    });
  });

  group('deleteSession', () {
    test('DELETE /api/sessions/{name}', () async {
      final t = FakeHttpTransport()
        ..on('DELETE', '/api/sessions/main', status: 204, body: '');
      final api = _makeApi(t);

      await api.deleteSession('main');

      final call = t.lastCallTo('DELETE', '/api/sessions/main')!;
      expect(call.url, '$_baseUrl/api/sessions/main');
      _expectBearer(call);
    });

    test('a session name with a slash is percent-encoded', () async {
      final t = FakeHttpTransport()
        ..on('DELETE', '/api/sessions/team%2Fmain', status: 204, body: '');
      final api = _makeApi(t);

      await api.deleteSession('team/main');

      expect(t.callCount('DELETE', '/api/sessions/team%2Fmain'), 1);
    });
  });

  group('getRepos', () {
    test('GET /api/repos — decodes full + minimal entries', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: reposFixture);
      final api = _makeApi(t);

      final repos = await api.getRepos();

      expect(repos, hasLength(2));
      expect(repos[0].name, 'bastion-ui');
      expect(repos[0].hasHandoff, isTrue);
      expect(repos[1].name, 'mev');
      expect(repos[1].hasHandoff, isFalse);
      _expectBearer(t.lastCallTo('GET', '/api/repos')!);
    });

    test('empty-collection fixture decodes to an empty list', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: reposEmptyFixture);
      final api = _makeApi(t);

      expect(await api.getRepos(), isEmpty);
    });
  });

  group('getRepoStatus', () {
    test('GET /api/repos/{name}/status — decoded value', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/bastion-ui/status',
          status: 200,
          body: repoStatusFullFixture,
        );
      final api = _makeApi(t);

      final status = await api.getRepoStatus('bastion-ui');

      expect(status.name, 'bastion-ui');
      expect(status.momentumNow, 'Task 2 in flight');
      _expectBearer(t.lastCallTo('GET', '/api/repos/bastion-ui/status')!);
    });

    test('repo name with a space is percent-encoded', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/my%20repo/status',
          status: 200,
          body: repoStatusMinimalFixture,
        );
      final api = _makeApi(t);

      await api.getRepoStatus('my repo');

      expect(t.callCount('GET', '/api/repos/my%20repo/status'), 1);
    });
  });

  group('getRepoHandoff', () {
    test('200 decodes HandoffInfo', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/bastion-ui/handoff',
          status: 200,
          body: handoffFullFixture,
        );
      final api = _makeApi(t);

      final handoff = await api.getRepoHandoff('bastion-ui');

      expect(handoff, isNotNull);
      expect(handoff!.title, 'Handoff — BU.ticket.integration-test-tier');
    });

    test('404/C002 decodes to null, not a thrown error', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/mev/handoff',
          status: 404,
          body: notFoundErrorFixture,
        );
      final api = _makeApi(t);

      final handoff = await api.getRepoHandoff('mev');

      expect(handoff, isNull);
    });

    test('a 404 with a different code still throws ApiError', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/mev/handoff',
          status: 404,
          body: {'error': 'gone', 'code': 'C999', 'message': 'gone'},
        );
      final api = _makeApi(t);

      expect(() => api.getRepoHandoff('mev'), throwsA(isA<ApiError>()));
    });
  });

  group('getRepoWorkflows', () {
    test('GET /api/repos/{name}/workflows — decoded list', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/bastion-ui/workflows',
          status: 200,
          body: workflowsFixture,
        );
      final api = _makeApi(t);

      final workflows = await api.getRepoWorkflows('bastion-ui');

      expect(workflows, hasLength(1));
      expect(workflows.single.specSlug, '2.A-dashboard-repo-detail');
      _expectBearer(t.lastCallTo('GET', '/api/repos/bastion-ui/workflows')!);
    });

    test('empty-collection fixture decodes to an empty list', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/repos/bastion-ui/workflows',
          status: 200,
          body: workflowsEmptyFixture,
        );
      final api = _makeApi(t);

      expect(await api.getRepoWorkflows('bastion-ui'), isEmpty);
    });
  });

  group('postCommand', () {
    test('inject mode — request body + decoded session', () async {
      final t = FakeHttpTransport()
        ..on(
          'POST',
          '/api/actions/command',
          status: 200,
          body: commandResponseFixture,
        );
      final api = _makeApi(t);

      final session = await api.postCommand(
        const CommandRequest(
          mode: CommandMode.inject,
          session: 'main',
          command: '/status',
        ),
      );

      expect(session, 'work');
      final call = t.lastCallTo('POST', '/api/actions/command')!;
      expect(
        call.body,
        '{"mode":"inject","session":"main","command":"/status"}',
      );
      _expectBearer(call);
    });

    test(
      'spawn mode — every optional field present in the request body',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'POST',
            '/api/actions/command',
            status: 200,
            body: commandResponseFixture,
          );
        final api = _makeApi(t);

        await api.postCommand(
          const CommandRequest(
            mode: CommandMode.spawn,
            name: 'work',
            dir: '/repo',
            model: CommandModel.opus,
            command: '/status',
          ),
        );

        final call = t.lastCallTo('POST', '/api/actions/command')!;
        expect(
          call.body,
          '{"mode":"spawn","name":"work","dir":"/repo","model":"opus","command":"/status"}',
        );
      },
    );
  });

  group('getBoard', () {
    test('no params — no query string emitted', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/board', status: 200, body: boardHqFixture);
      final api = _makeApi(t);

      final board = await api.getBoard();

      expect(board.scope, 'hq');
      expect(board.stale, isFalse);
      expect(board.lanes.now, hasLength(1));
      final block = board.lanes.now.single;
      expect(block.id, 'BA.11.K');
      expect(block.blockedBy, hasLength(5));
      final call = t.lastCallTo('GET', '/api/board')!;
      expect(call.queryParameters, isEmpty);
      _expectBearer(call);
    });

    test('every param emitted, graph=true only when requested', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/board', status: 200, body: boardProjectFixture);
      final api = _makeApi(t);

      await api.getBoard(
        scope: 'project',
        tier: 'core',
        repo: 'bastion-ui',
        epic: 'bastion-surfaces',
        graph: true,
      );

      final call = t.lastCallTo('GET', '/api/board')!;
      expect(call.queryParameters, {
        'scope': 'project',
        'tier': 'core',
        'repo': 'bastion-ui',
        'epic': 'bastion-surfaces',
        'graph': 'true',
      });
    });

    test('graph defaults to false — no graph param emitted', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/board', status: 200, body: boardHqFixture);
      final api = _makeApi(t);

      await api.getBoard(scope: 'hq');

      final call = t.lastCallTo('GET', '/api/board')!;
      expect(call.queryParameters.containsKey('graph'), isFalse);
    });

    test('empty-collection board fixture decodes with empty lanes', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/board', status: 200, body: boardEmptyFixture);
      final api = _makeApi(t);

      final board = await api.getBoard();

      expect(board.lanes.now, isEmpty);
      expect(board.repos, isEmpty);
    });
  });

  group('getLanes', () {
    test('no params — no query string emitted, decodes all segments', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/lanes', status: 200, body: lanesFixture);
      final api = _makeApi(t);

      final lanes = await api.getLanes();

      expect(lanes.derivedAt, '2026-08-18T10:00:00-07:00');
      expect(lanes.degraded, isFalse);
      expect(lanes.segments, hasLength(3));
      final startable = lanes.segments[0];
      expect(startable.roadmap, 'engine-orchestration');
      expect(startable.head, 'mev:MV.13.C');
      expect(startable.availability, 'startable');
      final done = lanes.segments[1];
      expect(done.head, isNull);
      expect(done.reason, isNull);
      final call = t.lastCallTo('GET', '/api/lanes')!;
      expect(call.queryParameters, isEmpty);
      _expectBearer(call);
    });

    test('epic param emitted when supplied', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/lanes', status: 200, body: lanesFixture);
      final api = _makeApi(t);

      await api.getLanes(epic: 'engine-orchestration');

      final call = t.lastCallTo('GET', '/api/lanes')!;
      expect(call.queryParameters, {'epic': 'engine-orchestration'});
    });

    test('known-but-unmatched epic decodes with empty segments', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/lanes', status: 200, body: lanesEmptyFixture);
      final api = _makeApi(t);

      final lanes = await api.getLanes(epic: 'no-such-epic');

      expect(lanes.segments, isEmpty);
    });
  });

  group('getAttention', () {
    test('no params — decoded lanes + thresholds', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/attention', status: 200, body: attentionFixture);
      final api = _makeApi(t);

      final attention = await api.getAttention();

      expect(attention.scope, 'hq');
      expect(attention.lanes.staleCarryover, hasLength(2));
      expect(attention.lanes.staleCarryover.first.repo, 'bastion-ui');
      expect(attention.thresholds.knownIssueDays, 10);
      final call = t.lastCallTo('GET', '/api/attention')!;
      expect(call.queryParameters, isEmpty);
      _expectBearer(call);
    });

    test('scope + tier are emitted as query params', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/attention', status: 200, body: attentionFixture);
      final api = _makeApi(t);

      await api.getAttention(scope: 'project', tier: 'core');

      final call = t.lastCallTo('GET', '/api/attention')!;
      expect(call.queryParameters, {'scope': 'project', 'tier': 'core'});
    });

    test('empty-collection fixture decodes to empty lanes', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/attention', status: 200, body: attentionEmptyFixture);
      final api = _makeApi(t);

      final attention = await api.getAttention();

      expect(attention.lanes.staleCarryover, isEmpty);
      expect(attention.lanes.agingBacklog, isEmpty);
      expect(attention.lanes.orphanedCaptures, isEmpty);
    });
  });

  group('getDocsTree', () {
    test('GET /api/docs/{repo}/tree — no path param', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/bastion-ui/tree',
          status: 200,
          body: docTreeFullFixture,
        );
      final api = _makeApi(t);

      final tree = await api.getDocsTree('bastion-ui');

      expect(tree.entries, hasLength(2));
      final call = t.lastCallTo('GET', '/api/docs/bastion-ui/tree')!;
      expect(call.queryParameters, isEmpty);
      _expectBearer(call);
    });

    test('path is emitted as a query param', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/bastion-ui/tree',
          status: 200,
          body: docTreeEmptyFixture,
        );
      final api = _makeApi(t);

      await api.getDocsTree('bastion-ui', path: 'planning');

      final call = t.lastCallTo('GET', '/api/docs/bastion-ui/tree')!;
      expect(call.queryParameters['path'], 'planning');
    });

    test('a repo name with a slash is percent-encoded in the path', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/some%2Frepo/tree',
          status: 200,
          body: docTreeEmptyFixture,
        );
      final api = _makeApi(t);

      await api.getDocsTree('some/repo');

      expect(t.callCount('GET', '/api/docs/some%2Frepo/tree'), 1);
    });

    test('empty-collection fixture decodes to an empty entries list', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/bastion-ui/tree',
          status: 200,
          body: docTreeEmptyFixture,
        );
      final api = _makeApi(t);

      final tree = await api.getDocsTree('bastion-ui');

      expect(tree.entries, isEmpty);
    });
  });

  group('getDocsFile', () {
    test(
      'GET /api/docs/{repo}/file — path is a required query param',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/docs/bastion-ui/file',
            status: 200,
            body: docFileFullFixture,
          );
        final api = _makeApi(t);

        final file = await api.getDocsFile(
          'bastion-ui',
          path: 'planning/status.md',
        );

        expect(file.content, '# Status\n\nOn track.\n');
        final call = t.lastCallTo('GET', '/api/docs/bastion-ui/file')!;
        expect(call.queryParameters, {'path': 'planning/status.md'});
        _expectBearer(call);
      },
    );

    test('a path with a space is query-encoded correctly', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/bastion-ui/file',
          status: 200,
          body: docFileMinimalFixture,
        );
      final api = _makeApi(t);

      await api.getDocsFile('bastion-ui', path: 'planning/my notes.md');

      final call = t.lastCallTo('GET', '/api/docs/bastion-ui/file')!;
      expect(call.queryParameters['path'], 'planning/my notes.md');
    });

    test('minimal fixture decodes with modified absent', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/docs/bastion-ui/file',
          status: 200,
          body: docFileMinimalFixture,
        );
      final api = _makeApi(t);

      final file = await api.getDocsFile(
        'bastion-ui',
        path: 'planning/empty.md',
      );

      expect(file.modified, isNull);
      expect(file.content, '');
    });
  });

  group('getRuns', () {
    test('GET /api/runs — bearer header, decodes populated list', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/runs', status: 200, body: runsFixture);
      final api = _makeApi(t);

      final runs = await api.getRuns();

      expect(runs, hasLength(3));
      expect(runs[0].runId, 'b6a1c1e0-0000-4000-8000-000000000000');
      expect(runs[0].status, 'running');
      expect(runs[2].status, 'suspended');
      _expectBearer(t.lastCallTo('GET', '/api/runs')!);
    });

    test('empty-collection fixture decodes to an empty list — no engine '
        'mounted is a valid success, not an error', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/runs', status: 200, body: runsEmptyFixture);
      final api = _makeApi(t);

      expect(await api.getRuns(), isEmpty);
    });

    test('401 yields FatalAuthError, not retried', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/runs', status: 401, body: unauthorizedErrorFixture);
      final api = _makeApi(t);

      await expectLater(() => api.getRuns(), throwsA(isA<FatalAuthError>()));

      expect(t.callCount('GET', '/api/runs'), 1);
    });
  });

  group('getRun', () {
    test(
      'GET /api/runs/{id} — decodes node list, no aggregate status',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/runs/b6a1c1e0-0000-4000-8000-000000000000',
            status: 200,
            body: runStateFullFixture,
          );
        final api = _makeApi(t);

        final state = await api.getRun('b6a1c1e0-0000-4000-8000-000000000000');

        expect(state.runId, 'b6a1c1e0-0000-4000-8000-000000000000');
        expect(state.nodes, isNotEmpty);
        _expectBearer(
          t.lastCallTo(
            'GET',
            '/api/runs/b6a1c1e0-0000-4000-8000-000000000000',
          )!,
        );
      },
    );

    test('run id needing escaping is percent-encoded', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/runs/run%20id%20with%20spaces',
          status: 200,
          body: runStateEmptyFixture,
        );
      final api = _makeApi(t);

      await api.getRun('run id with spaces');

      expect(t.callCount('GET', '/api/runs/run%20id%20with%20spaces'), 1);
    });

    test('401 yields FatalAuthError, not retried', () async {
      final t = FakeHttpTransport()
        ..on(
          'GET',
          '/api/runs/b6a1c1e0-0000-4000-8000-000000000000',
          status: 401,
          body: unauthorizedErrorFixture,
        );
      final api = _makeApi(t);

      await expectLater(
        () => api.getRun('b6a1c1e0-0000-4000-8000-000000000000'),
        throwsA(isA<FatalAuthError>()),
      );

      expect(
        t.callCount('GET', '/api/runs/b6a1c1e0-0000-4000-8000-000000000000'),
        1,
      );
    });
  });

  // ---------------------------------------------------------------------
  // Error contract — applies uniformly across every route; exercised here
  // once per distinct failure mode using getRepos as the representative
  // route (any route wires through the same `_decode`/`_decodeList`
  // helpers in `BastionApi`).
  // ---------------------------------------------------------------------

  group('error contract', () {
    test('401 yields FatalAuthError and is not retried', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 401, body: unauthorizedErrorFixture);
      final api = _makeApi(t);

      await expectLater(() => api.getRepos(), throwsA(isA<FatalAuthError>()));

      expect(t.callCount('GET', '/api/repos'), 1);
    });

    test(
      'a non-2xx non-401 surfaces as ApiError, not an empty success',
      () async {
        final t = FakeHttpTransport()
          ..on(
            'GET',
            '/api/repos',
            status: 500,
            body: {'error': 'boom', 'code': 'C010', 'message': 'server error'},
          );
        final api = _makeApi(t);

        await expectLater(
          () => api.getRepos(),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      },
    );

    test('a 200 carrying malformed JSON fails loudly as ApiError', () async {
      final t = FakeHttpTransport()
        ..on('GET', '/api/repos', status: 200, body: 'not json at all {{{');
      final api = _makeApi(t);

      await expectLater(() => api.getRepos(), throwsA(isA<ApiError>()));
    });

    test(
      'a 200 carrying a JSON object where a list is expected fails loudly',
      () async {
        final t = FakeHttpTransport()
          ..on('GET', '/api/repos', status: 200, body: {'not': 'a list'});
        final api = _makeApi(t);

        await expectLater(() => api.getRepos(), throwsA(isA<ApiError>()));
      },
    );

    test(
      'FatalAuthError with malformed 401 body still throws typed error',
      () async {
        final t = FakeHttpTransport()
          ..on('GET', '/api/repos', status: 401, body: 'not json');
        final api = _makeApi(t);

        await expectLater(() => api.getRepos(), throwsA(isA<FatalAuthError>()));
      },
    );
  });
}
