// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/state/workflows_provider.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors sessions_provider_test.dart / events_provider_test.dart)
// ---------------------------------------------------------------------------

class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void addMessage(String msg) => _controller.add(msg);

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<dynamic> get messageStream => _controller.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

class FakeHttpTransport implements HttpTransport {
  final List<({int statusCode, String body})> _responses = [];
  int getCallCount = 0;

  void setResponse({required int statusCode, required Object body}) {
    final encoded = body is String ? body : jsonEncode(body);
    _responses.add((statusCode: statusCode, body: encoded));
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    getCallCount++;
    if (_responses.isEmpty) {
      throw StateError('FakeHttpTransport: no response queued for GET $url');
    }
    return _responses.removeAt(0);
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError('not exercised by this test');
}

/// Uses a real (non-zero) delay per round so rxdart's `.debounceTime(~150ms)`
/// on the per-repo `workflow_done` stream (see
/// `lib/state/workflows_provider.dart`) has enough wall-clock time to fire
/// within the default 5 rounds (200ms total).
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<(BastionSocket, FakeWsTransport)> makeConnectedSocket() async {
  final transports = <FakeWsTransport>[];
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      transports.add(t);
      return t;
    },
  );
  socket.connect();
  await pump();
  transports.single.completeReady();
  await pump();
  return (socket, transports.single);
}

Map<String, dynamic> statusJson({String name = 'bastion-ui'}) => {
  'name': name,
  'now': 'wiring dashboard',
  'next': 'repo detail',
  'blocked': '',
  'has_handoff': true,
  'momentum_now': 'n',
  'momentum_next': 'x',
  'momentum_blocked': 'b',
  'momentum_improve': 'i',
  'momentum_recurring': 'r',
};

String workflowDoneEventJson(String repo, {String status = 'done'}) =>
    jsonEncode({
      'kind': 'event',
      'payload': {
        'session': '',
        'event': 'workflow_done',
        'repo': repo,
        'spec_slug': '2.A-dashboard-repo-detail',
        'status': status,
      },
    });

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('workflowDoneEventsProvider', () {
    test('throws StateError when read before socket is set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container.read(workflowDoneEventsProvider),
        throwsA(isA<StateError>()),
      );
    });

    test('emits only "workflow_done" events, ignoring other kinds', () async {
      final (socket, transport) = await makeConnectedSocket();
      addTearDown(() => socket.dispose());
      final container = ProviderContainer(
        overrides: [bastionSocketProvider.overrideWith((ref) => socket)],
      );
      addTearDown(container.dispose);

      final received = <EventFrame>[];
      final sub = container
          .read(workflowDoneEventsProvider)
          .listen(received.add);
      addTearDown(sub.cancel);

      transport.addMessage(workflowDoneEventJson('bastion-ui'));
      transport.addMessage(
        jsonEncode({
          'kind': 'event',
          'payload': {'session': 'sess-a', 'event': 'needs_input'},
        }),
      );
      await pump();

      expect(received, hasLength(1));
      expect(received.single.event, 'workflow_done');
      expect(received.single.extra['repo'], 'bastion-ui');
    });
  });

  group('repoWorkflowsProvider', () {
    late BastionSocket socket;
    late FakeWsTransport transport;
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer container;

    setUp(() async {
      final (s, t) = await makeConnectedSocket();
      socket = s;
      transport = t;
      httpTransport = FakeHttpTransport();
      api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: httpTransport,
      );
    });

    tearDown(() async {
      container.dispose();
      await socket.dispose();
    });

    test('throws StateError when read before api is set', () {
      container = ProviderContainer(
        overrides: [bastionSocketProvider.overrideWith((ref) => socket)],
      );
      expect(
        () => container.read(repoWorkflowsProvider('bastion-ui')),
        throwsA(isA<StateError>()),
      );
    });

    test('seeds status + workflows from REST on first watch', () async {
      httpTransport.setResponse(statusCode: 200, body: statusJson());
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {
            'spec_slug': '2.A-dashboard-repo-detail',
            'branch': '2.A-dashboard-repo-detail-flow',
            'status': 'running',
            'current_task': 3,
            'started_at': '2026-07-02T00:00:00Z',
            'updated_at': '2026-07-02T00:05:00Z',
          },
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(repoWorkflowsProvider('bastion-ui'));
      await pump();

      final state = container.read(repoWorkflowsProvider('bastion-ui'));
      expect(state.loading, isFalse);
      expect(state.status?.now, 'wiring dashboard');
      expect(state.workflows, hasLength(1));
      expect(state.workflows.single.status, 'running');
    });

    test(
      'a matching workflow_done event triggers a re-fetch that updates state',
      () async {
        httpTransport.setResponse(statusCode: 200, body: statusJson());
        httpTransport.setResponse(statusCode: 200, body: <dynamic>[]);
        container = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
        );
        container.read(repoWorkflowsProvider('bastion-ui'));
        await pump();
        expect(
          container.read(repoWorkflowsProvider('bastion-ui')).workflows,
          isEmpty,
        );

        httpTransport.setResponse(
          statusCode: 200,
          body: statusJson()..['now'] = 'done',
        );
        httpTransport.setResponse(
          statusCode: 200,
          body: [
            {
              'spec_slug': '2.A-dashboard-repo-detail',
              'branch': '2.A-dashboard-repo-detail-flow',
              'status': 'done',
              'current_task': 8,
              'started_at': '2026-07-02T00:00:00Z',
              'updated_at': '2026-07-02T01:00:00Z',
            },
          ],
        );

        transport.addMessage(workflowDoneEventJson('bastion-ui'));
        await pump();

        final state = container.read(repoWorkflowsProvider('bastion-ui'));
        expect(state.status?.now, 'done');
        expect(state.workflows.single.status, 'done');
      },
    );

    test('a workflow_done event for a different repo is ignored', () async {
      httpTransport.setResponse(statusCode: 200, body: statusJson());
      httpTransport.setResponse(statusCode: 200, body: <dynamic>[]);
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      container.read(repoWorkflowsProvider('bastion-ui'));
      await pump();

      // No further responses queued — if a re-fetch were (incorrectly)
      // triggered, the FakeHttpTransport would throw for lack of a queued
      // response, failing the test.
      transport.addMessage(workflowDoneEventJson('some-other-repo'));
      await pump();

      expect(httpTransport.getCallCount, 2);
    });
  });
}
