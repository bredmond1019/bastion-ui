// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
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

  group('EngineApi.pauseRun', () {
    test('hits POST /events/{run_id}/pause with no /api prefix and '
        'X-API-Key', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/pause',
        status: 202,
        body: {'run_id': 'run-1', 'status': 'pausing'},
      );
      final engine = makeEngine(t);

      await engine.pauseRun('run-1');

      expect(t.calls.single.url, 'http://127.0.0.1:4317/events/run-1/pause');
      expect(t.calls.single.url.contains('/api'), isFalse);
      expect(t.calls.single.headers['X-API-Key'], _sentinelKey);
    });

    test('202 maps to PausePausing, named for the in-flight verb', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/pause',
        status: 202,
        body: {'run_id': 'run-1', 'status': 'pausing'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.pauseRun('run-1');

      expect(outcome, isA<PausePausing>());
      expect((outcome as PausePausing).runId, 'run-1');
      expect(outcome.status, 'pausing');
    });

    test('409 maps to PauseAlreadySuspended', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/pause',
        status: 409,
        body: {
          'run_id': 'run-1',
          'status': 'suspended',
          'error': 'run is already suspended',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.pauseRun('run-1');

      expect(outcome, isA<PauseAlreadySuspended>());
      expect(
        (outcome as PauseAlreadySuspended).error,
        'run is already suspended',
      );
    });

    test('404 maps to PauseNotFound', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/pause',
        status: 404,
        body: {'error': 'unknown or finished run'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.pauseRun('run-1');

      expect(outcome, isA<PauseNotFound>());
      expect((outcome as PauseNotFound).error, 'unknown or finished run');
    });

    test('401 surfaces as FatalAuthError', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/pause',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(
        engine.pauseRun('run-1'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('a not-configured client issues zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.pauseRun('run-1'),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('EngineApi.resumeRun', () {
    test('hits POST /events/{event_id}/resume with no /api prefix and '
        'X-API-Key', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 202,
        body: {
          'run_id': 'run-1',
          'event_id': 'evt-1',
          'status': 'resuming',
          'resume_at': '2026-08-18T00:00:00Z',
        },
      );
      final engine = makeEngine(t);

      await engine.resumeRun('evt-1');

      expect(t.calls.single.url, 'http://127.0.0.1:4317/events/evt-1/resume');
      expect(t.calls.single.url.contains('/api'), isFalse);
      expect(t.calls.single.headers['X-API-Key'], _sentinelKey);
    });

    test('202 maps to ResumeResuming, named for the in-flight verb', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 202,
        body: {
          'run_id': 'run-1',
          'event_id': 'evt-1',
          'status': 'resuming',
          'resume_at': '2026-08-18T00:00:00Z',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.resumeRun('evt-1');

      expect(outcome, isA<ResumeResuming>());
      final resuming = outcome as ResumeResuming;
      expect(resuming.runId, 'run-1');
      expect(resuming.eventId, 'evt-1');
      expect(resuming.status, 'resuming');
      expect(resuming.resumeAt, '2026-08-18T00:00:00Z');
    });

    test('409 maps to ResumeAlreadyResuming', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 409,
        body: {'error': 'resume already in flight'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.resumeRun('evt-1');

      expect(outcome, isA<ResumeAlreadyResuming>());
      expect(
        (outcome as ResumeAlreadyResuming).error,
        'resume already in flight',
      );
    });

    test('404 maps to ResumeNotFound', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 404,
        body: {'error': 'unknown or non-resumable run'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.resumeRun('evt-1');

      expect(outcome, isA<ResumeNotFound>());
      expect((outcome as ResumeNotFound).error, 'unknown or non-resumable run');
    });

    test('422 maps to ResumePolicyFailed and carries the server message '
        'through', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 422,
        body: {
          'error': 'policy resolution failed',
          'message': 'unknown workflow_type: mystery-flow',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.resumeRun('evt-1');

      expect(outcome, isA<ResumePolicyFailed>());
      final failed = outcome as ResumePolicyFailed;
      expect(failed.error, 'policy resolution failed');
      expect(failed.message, 'unknown workflow_type: mystery-flow');
    });

    test('401 surfaces as FatalAuthError', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/evt-1/resume',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(
        engine.resumeRun('evt-1'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('a not-configured client issues zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.resumeRun('evt-1'),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('EngineApi.abortRun', () {
    test('hits POST /events/{run_id}/abort with no /api prefix and '
        'X-API-Key', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/abort',
        status: 202,
        body: {'run_id': 'run-1', 'status': 'aborting'},
      );
      final engine = makeEngine(t);

      await engine.abortRun('run-1');

      expect(t.calls.single.url, 'http://127.0.0.1:4317/events/run-1/abort');
      expect(t.calls.single.url.contains('/api'), isFalse);
      expect(t.calls.single.headers['X-API-Key'], _sentinelKey);
    });

    test('202 maps to AbortAborting, named for the in-flight verb', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/abort',
        status: 202,
        body: {'run_id': 'run-1', 'status': 'aborting'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.abortRun('run-1');

      expect(outcome, isA<AbortAborting>());
      expect((outcome as AbortAborting).runId, 'run-1');
      expect(outcome.status, 'aborting');
    });

    test('404 maps to AbortNotFound', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/abort',
        status: 404,
        body: {'error': 'unknown or finished run'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.abortRun('run-1');

      expect(outcome, isA<AbortNotFound>());
      expect((outcome as AbortNotFound).error, 'unknown or finished run');
    });

    test('401 surfaces as FatalAuthError', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/run-1/abort',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(
        engine.abortRun('run-1'),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('a not-configured client issues zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.abortRun('run-1'),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('EngineApi.listSuspended', () {
    test(
      'hits GET /events/suspended with no /api prefix and X-API-Key',
      () async {
        final t = FakeHttpTransport();
        t.on('GET', '/events/suspended', status: 200, body: []);
        final engine = makeEngine(t);

        await engine.listSuspended();

        expect(t.calls.single.url, 'http://127.0.0.1:4317/events/suspended');
        expect(t.calls.single.url.contains('/api'), isFalse);
        expect(t.calls.single.headers['X-API-Key'], _sentinelKey);
      },
    );

    test(
      'parses each row and preserves server ordering (newest first)',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'GET',
          '/events/suspended',
          status: 200,
          body: [
            {
              'run_id': 'run-2',
              'workflow_type': 'deploy',
              'created_at': '2026-08-17T00:00:00Z',
              'suspended_at': '2026-08-18T00:00:00Z',
              'resume_at': null,
              'reason': 'operator-paused',
            },
            {
              'run_id': 'run-1',
              'workflow_type': 'ingest',
              'created_at': '2026-08-16T00:00:00Z',
              'suspended_at': '2026-08-16T01:00:00Z',
              'resume_at': '2026-08-19T00:00:00Z',
              'reason': 'awaiting-approval',
            },
          ],
        );
        final engine = makeEngine(t);

        final rows = await engine.listSuspended();

        expect(rows, hasLength(2));
        expect(rows[0].runId, 'run-2');
        expect(rows[0].workflowType, 'deploy');
        expect(rows[0].reason, 'operator-paused');
        expect(rows[1].runId, 'run-1');
        expect(rows[1].resumeAt, '2026-08-19T00:00:00Z');
      },
    );

    test('401 surfaces as FatalAuthError', () async {
      final t = FakeHttpTransport();
      t.on(
        'GET',
        '/events/suspended',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(engine.listSuspended(), throwsA(isA<FatalAuthError>()));
    });

    test('a not-configured client issues zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.listSuspended(),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('EngineApi.launchRun', () {
    test('hits POST /events/ with no /api prefix, JSON content-type, and the '
        'exact {workflow_type, data} body shape', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 202,
        body: {'run_id': 'run-1', 'event_id': 'evt-1'},
      );
      final engine = makeEngine(t);

      await engine.launchRun(
        workflowType: 'SDLC_FLOW',
        data: {'repo': 'bastion-ui', 'spec_slug': 'BU.12.E'},
      );

      final call = t.calls.single;
      expect(call.method, 'POST');
      expect(call.url, 'http://127.0.0.1:4317/events/');
      expect(call.url.contains('/api'), isFalse);
      expect(call.headers['X-API-Key'], _sentinelKey);
      expect(call.headers['Content-Type'], 'application/json');
      expect(jsonDecode(call.body!), {
        'workflow_type': 'SDLC_FLOW',
        'data': {'repo': 'bastion-ui', 'spec_slug': 'BU.12.E'},
      });
    });

    test('202 maps to LaunchAccepted carrying run_id and event_id', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 202,
        body: {'run_id': 'run-1', 'event_id': 'evt-1'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.launchRun(
        workflowType: 'SDLC_FLOW',
        data: {},
      );

      expect(outcome, isA<LaunchAccepted>());
      expect((outcome as LaunchAccepted).runId, 'run-1');
      expect(outcome.eventId, 'evt-1');
    });

    test('401 surfaces as FatalAuthError', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 401,
        body: {'error': 'unauthorized', 'code': 'unauthorized'},
      );
      final engine = makeEngine(t);

      await expectLater(
        engine.launchRun(workflowType: 'SDLC_FLOW', data: const {}),
        throwsA(isA<FatalAuthError>()),
      );
    });

    test('422 unknown workflow_type maps to LaunchUnknownWorkflowType naming '
        'it', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {'error': 'unknown workflow_type', 'workflow_type': 'BOGUS'},
      );
      final engine = makeEngine(t);

      final outcome = await engine.launchRun(
        workflowType: 'BOGUS',
        data: const {},
      );

      expect(outcome, isA<LaunchUnknownWorkflowType>());
      expect((outcome as LaunchUnknownWorkflowType).workflowType, 'BOGUS');
    });

    test(
      '422 unknown repo maps to LaunchUnknownRepo carrying repo and message',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'unknown repo',
            'repo': 'no-such-repo',
            'message': 'no repo named no-such-repo is registered',
          },
        );
        final engine = makeEngine(t);

        final outcome = await engine.launchRun(
          workflowType: 'SDLC_FLOW',
          data: {'repo': 'no-such-repo'},
        );

        expect(outcome, isA<LaunchUnknownRepo>());
        final unknownRepo = outcome as LaunchUnknownRepo;
        expect(unknownRepo.repo, 'no-such-repo');
        expect(unknownRepo.message, 'no repo named no-such-repo is registered');
      },
    );

    test('422 unknown spec_slug maps to LaunchUnknownSpecSlug carrying the '
        'slug and message', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {
          'error': 'unknown spec_slug',
          'spec_slug': 'NO.SUCH.SLUG',
          'message': 'no spec named NO.SUCH.SLUG exists',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.launchRun(
        workflowType: 'SDLC_FLOW',
        data: {'spec_slug': 'NO.SUCH.SLUG'},
      );

      expect(outcome, isA<LaunchUnknownSpecSlug>());
      final unknownSlug = outcome as LaunchUnknownSpecSlug;
      expect(unknownSlug.specSlug, 'NO.SUCH.SLUG');
      expect(unknownSlug.message, 'no spec named NO.SUCH.SLUG exists');
    });

    test('422 policy resolution failed maps to LaunchPolicyFailed carrying '
        'the message', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {
          'error': 'policy resolution failed',
          'message': 'no policy resolves for this workflow_type',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.launchRun(
        workflowType: 'SDLC_FLOW',
        data: const {},
      );

      expect(outcome, isA<LaunchPolicyFailed>());
      expect(
        (outcome as LaunchPolicyFailed).message,
        'no policy resolves for this workflow_type',
      );
    });

    test('422 unresolvable target root maps to LaunchUnresolvableTargetRoot '
        'carrying the message', () async {
      final t = FakeHttpTransport();
      t.on(
        'POST',
        '/events/',
        status: 422,
        body: {
          'error': 'unresolvable target root',
          'message': 'no target root could be resolved',
        },
      );
      final engine = makeEngine(t);

      final outcome = await engine.launchRun(
        workflowType: 'SDLC_FLOW',
        data: const {},
      );

      expect(outcome, isA<LaunchUnresolvableTargetRoot>());
      expect(
        (outcome as LaunchUnresolvableTargetRoot).message,
        'no target root could be resolved',
      );
    });

    test(
      'an unrecognised 422 error string falls back to LaunchUnknownRejection '
      'carrying the raw body',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/',
          status: 422,
          body: {
            'error': 'some future rejection class the client does not know',
            'detail': 'added upstream after this client was written',
          },
        );
        final engine = makeEngine(t);

        final outcome = await engine.launchRun(
          workflowType: 'SDLC_FLOW',
          data: const {},
        );

        expect(outcome, isA<LaunchUnknownRejection>());
        final rejection = outcome as LaunchUnknownRejection;
        expect(
          rejection.rawBody,
          contains('some future rejection class the client does not know'),
        );
        expect(
          rejection.rawBody,
          contains('added upstream after this client was written'),
        );
      },
    );

    test('a not-configured client issues zero requests', () async {
      final t = FakeHttpTransport();
      final engine = makeEngine(t, key: null);

      await expectLater(
        engine.launchRun(workflowType: 'SDLC_FLOW', data: const {}),
        throwsA(isA<EngineNotConfiguredError>()),
      );
      expect(t.calls, isEmpty);
    });

    test(
      'the sentinel key appears nowhere in a launch 401 toString()',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/',
          status: 401,
          body: {'error': 'unauthorized', 'code': 'unauthorized'},
        );
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.launchRun(workflowType: 'SDLC_FLOW', data: const {});
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );

    test(
      'the sentinel key appears nowhere in a launch 500 toString()',
      () async {
        final t = FakeHttpTransport();
        t.on('POST', '/events/', status: 500, body: 'internal error');
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.launchRun(workflowType: 'SDLC_FLOW', data: const {});
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );
  });

  group('leak assertion — control routes (Standing Rule 7)', () {
    test(
      'the sentinel key appears nowhere in a pause 401 toString()',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/run-1/pause',
          status: 401,
          body: {'error': 'unauthorized', 'code': 'unauthorized'},
        );
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.pauseRun('run-1');
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );

    test(
      'the sentinel key appears nowhere in a resume 500 toString()',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/evt-1/resume',
          status: 500,
          body: 'internal error',
        );
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.resumeRun('evt-1');
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );

    test(
      'the sentinel key appears nowhere in an abort 500 toString()',
      () async {
        final t = FakeHttpTransport();
        t.on(
          'POST',
          '/events/run-1/abort',
          status: 500,
          body: 'internal error',
        );
        final engine = makeEngine(t);

        Object? caught;
        try {
          await engine.abortRun('run-1');
        } catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(caught.toString().contains(_sentinelKey), isFalse);
      },
    );
  });
}
