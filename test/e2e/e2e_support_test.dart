// ignore_for_file: avoid_relative_lib_imports

/// Gating unit tests for `test/e2e/e2e_support.dart`.
///
/// Not tagged `e2e` — runs in `flutter test --exclude-tags e2e` with no real
/// `bastion serve` or `tmux` binary. Uses a fake [WsTransport] (mirroring
/// `test/services/reconnect_test.dart`'s `FakeWsTransport`) and a fake
/// [HttpTransport] to exercise [subscribeAndCollect], [withManagedSession],
/// [collectEvents], and [writeFixtureFlowState] hermetically.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/pane_provider.dart' show paneTopic;

import 'e2e_support.dart';

// ---------------------------------------------------------------------------
// Fake WS transport (same pattern as test/services/reconnect_test.dart)
// ---------------------------------------------------------------------------

class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void addMessage(String msg) => _controller.add(msg);

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<dynamic> get messageStream => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

/// Pump the Dart event / microtask queue [rounds] times.
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

BastionSocket makeSocket(List<FakeWsTransport> transports) {
  return BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      transports.add(t);
      return t;
    },
    backoffSchedule: (_) => Duration.zero,
  );
}

// ---------------------------------------------------------------------------
// Fake HTTP transport (for BastionApi)
// ---------------------------------------------------------------------------

class FakeHttpTransport implements HttpTransport {
  final List<String> createdSessions = [];
  final List<String> deletedSessions = [];

  /// When set, [post] to the sessions-create endpoint throws this instead
  /// of recording the call.
  Object? createError;

  /// When set, [delete] throws this instead of recording the call.
  Object? deleteError;

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return (statusCode: 200, body: '{}');
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (url.endsWith('/api/sessions')) {
      if (createError != null) throw createError!;
      final decoded = jsonDecode(body ?? '{}') as Map<String, dynamic>;
      createdSessions.add(decoded['name'] as String);
      return (statusCode: 201, body: '{}');
    }
    return (statusCode: 204, body: '');
  }

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (deleteError != null) throw deleteError!;
    final name = Uri.decodeComponent(url.split('/').last);
    deletedSessions.add(name);
    return (statusCode: 204, body: '');
  }
}

BastionApi makeApi(FakeHttpTransport transport) => BastionApi(
  host: 'test-host',
  port: 4317,
  token: 'test-token',
  transport: transport,
);

void main() {
  // -------------------------------------------------------------------------
  // tmuxAvailable
  // -------------------------------------------------------------------------
  group('tmuxAvailable', () {
    test('returns a bool without throwing', () {
      expect(() => tmuxAvailable(), returnsNormally);
      expect(tmuxAvailable(), isA<bool>());
    });
  });

  // -------------------------------------------------------------------------
  // subscribeAndCollect
  // -------------------------------------------------------------------------
  group('subscribeAndCollect', () {
    test(
      'sends subscribe frame and resolves with topic-matching frames',
      () async {
        final transports = <FakeWsTransport>[];
        final socket = makeSocket(transports);
        socket.connect();
        transports[0].completeReady();
        await pump();

        final topic = paneTopic('demo');
        final future = subscribeAndCollect(
          socket,
          topic: topic,
          count: 2,
          timeout: const Duration(seconds: 5),
        );
        await pump();

        // Subscribe frame was sent before any frames were pushed.
        expect(transports[0].sent, hasLength(1));
        final sentJson =
            jsonDecode(transports[0].sent.first) as Map<String, dynamic>;
        expect(sentJson['kind'], 'subscribe');
        expect(sentJson['payload'], {'topic': topic});

        // A non-matching frame (different session) should not count.
        transports[0].addMessage(
          jsonEncode({
            'kind': 'pane',
            'payload': {
              'session': 'other',
              'seq': 1,
              'lines': ['x'],
            },
          }),
        );
        await pump();

        transports[0].addMessage(
          jsonEncode({
            'kind': 'pane',
            'payload': {
              'session': 'demo',
              'seq': 1,
              'lines': ['hello'],
            },
          }),
        );
        transports[0].addMessage(
          jsonEncode({
            'kind': 'pane',
            'payload': {
              'session': 'demo',
              'seq': 2,
              'lines': ['world'],
            },
          }),
        );
        await pump();

        final result = await future;
        expect(result, hasLength(2));
        expect(result.every((f) => f is PaneFrame), isTrue);
        expect((result[0] as PaneFrame).lines, ['hello']);
        expect((result[1] as PaneFrame).lines, ['world']);

        // unsubscribe was sent once collection completed.
        expect(transports[0].sent, hasLength(2));
        final unsubJson =
            jsonDecode(transports[0].sent.last) as Map<String, dynamic>;
        expect(unsubJson['kind'], 'unsubscribe');
        expect(unsubJson['payload'], {'topic': topic});

        await socket.dispose();
      },
    );

    test('throws TimeoutException when too few frames arrive', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      socket.connect();
      transports[0].completeReady();
      await pump();

      final topic = paneTopic('demo');
      final future = subscribeAndCollect(
        socket,
        topic: topic,
        count: 2,
        timeout: const Duration(milliseconds: 20),
      );

      // Only one matching frame arrives — not enough.
      transports[0].addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'demo',
            'seq': 1,
            'lines': ['hello'],
          },
        }),
      );

      await expectLater(future, throwsA(isA<TimeoutException>()));

      await socket.dispose();
    });

    test(
      'registers the subscription before sending, avoiding a lost frame',
      () async {
        final transports = <FakeWsTransport>[];
        final socket = makeSocket(transports);
        socket.connect();
        transports[0].completeReady();
        await pump();

        final topic = 'sessions';
        final future = subscribeAndCollect(
          socket,
          topic: topic,
          count: 1,
          timeout: const Duration(seconds: 5),
        );

        // Push the response frame synchronously right after the call returns
        // (before any extra pump/microtask yield) — this only resolves
        // correctly if the listener was registered before send() was called.
        transports[0].addMessage(
          jsonEncode({
            'kind': 'sessions',
            'payload': {'sessions': []},
          }),
        );

        final result = await future;
        expect(result, hasLength(1));
        expect(result.first, isA<SessionsFrame>());

        await socket.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // withManagedSession
  // -------------------------------------------------------------------------
  group('withManagedSession', () {
    test('returns callback value and deletes the session on success', () async {
      final transport = FakeHttpTransport();
      final api = makeApi(transport);

      final result = await withManagedSession<String>(
        api,
        (name) async => 'ok:$name',
        name: 'my-session',
      );

      expect(result, 'ok:my-session');
      expect(transport.createdSessions, ['my-session']);
      expect(transport.deletedSessions, ['my-session']);
    });

    test(
      'deletes the session in finally and rethrows when callback throws',
      () async {
        final transport = FakeHttpTransport();
        final api = makeApi(transport);

        await expectLater(
          withManagedSession<void>(
            api,
            (name) async => throw StateError('boom'),
            name: 'my-session',
          ),
          throwsA(isA<StateError>()),
        );

        expect(transport.createdSessions, ['my-session']);
        expect(
          transport.deletedSessions,
          ['my-session'],
          reason: 'cleanup must still run when the callback throws',
        );
      },
    );

    test('a cleanup failure does not mask the original result', () async {
      final transport = FakeHttpTransport()
        ..deleteError = Exception('delete failed');
      final api = makeApi(transport);

      final result = await withManagedSession<String>(
        api,
        (name) async => 'ok:$name',
        name: 'my-session',
      );

      expect(result, 'ok:my-session');
    });
  });

  // -------------------------------------------------------------------------
  // collectEvents
  // -------------------------------------------------------------------------
  group('collectEvents', () {
    test('does not send a subscribe frame', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      socket.connect();
      transports[0].completeReady();
      await pump();

      final future = collectEvents(
        socket,
        event: 'workflow_done',
        count: 1,
        timeout: const Duration(seconds: 5),
      );
      await pump();

      expect(
        transports[0].sent,
        isEmpty,
        reason: 'event frames are broadcast with no subscribe topic',
      );

      transports[0].addMessage(
        jsonEncode({
          'kind': 'event',
          'payload': {
            'session': '',
            'event': 'workflow_done',
            'repo': 'fixture-repo',
            'spec_slug': '8B-workflow-done',
            'status': 'done',
          },
        }),
      );

      final result = await future;
      expect(result, hasLength(1));
      expect(result.single.event, 'workflow_done');
      expect(result.single.extra['repo'], 'fixture-repo');
      expect(result.single.extra['spec_slug'], '8B-workflow-done');
      expect(result.single.extra['status'], 'done');

      await socket.dispose();
    });

    test('ignores event frames with a different event name', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      socket.connect();
      transports[0].completeReady();
      await pump();

      final future = collectEvents(
        socket,
        event: 'workflow_done',
        count: 1,
        timeout: const Duration(milliseconds: 50),
      );

      transports[0].addMessage(
        jsonEncode({
          'kind': 'event',
          'payload': {'session': '', 'event': 'something_else'},
        }),
      );

      await expectLater(future, throwsA(isA<TimeoutException>()));

      await socket.dispose();
    });

    test(
      'ignores non-event frames and collects the Nth matching event',
      () async {
        final transports = <FakeWsTransport>[];
        final socket = makeSocket(transports);
        socket.connect();
        transports[0].completeReady();
        await pump();

        final future = collectEvents(
          socket,
          event: 'workflow_done',
          count: 2,
          timeout: const Duration(seconds: 5),
        );
        await pump();

        transports[0].addMessage(
          jsonEncode({
            'kind': 'sessions',
            'payload': {'sessions': []},
          }),
        );
        transports[0].addMessage(
          jsonEncode({
            'kind': 'event',
            'payload': {
              'session': '',
              'event': 'workflow_done',
              'repo': 'a',
              'spec_slug': 's1',
              'status': 'done',
            },
          }),
        );
        transports[0].addMessage(
          jsonEncode({
            'kind': 'event',
            'payload': {
              'session': '',
              'event': 'workflow_done',
              'repo': 'b',
              'spec_slug': 's2',
              'status': 'error',
            },
          }),
        );
        await pump();

        final result = await future;
        expect(result, hasLength(2));
        expect(result[0].extra['repo'], 'a');
        expect(result[1].extra['repo'], 'b');

        await socket.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // writeFixtureFlowState
  // -------------------------------------------------------------------------
  group('writeFixtureFlowState', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('e2e_support_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    });

    test(
      'writes a valid JSON file at planningDir/specSlug/sdlc/sdlc-flow-state.json',
      () async {
        await writeFixtureFlowState(
          tempDir.path,
          specSlug: '8B-workflow-done',
          status: 'running',
        );

        final file = File(
          '${tempDir.path}/8B-workflow-done/sdlc/sdlc-flow-state.json',
        );
        expect(file.existsSync(), isTrue);

        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(decoded['spec_slug'], '8B-workflow-done');
        expect(decoded['status'], 'running');
        expect(decoded.containsKey('pr'), isFalse);
      },
    );

    test('includes pr field when provided', () async {
      await writeFixtureFlowState(
        tempDir.path,
        specSlug: '8B-workflow-done',
        status: 'done',
        pr: 'https://example/pr/1',
      );

      final file = File(
        '${tempDir.path}/8B-workflow-done/sdlc/sdlc-flow-state.json',
      );
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['pr'], 'https://example/pr/1');
    });

    test('creates parent directories recursively', () async {
      final nestedPlanningDir = '${tempDir.path}/repos/fixture-repo/planning';
      await writeFixtureFlowState(
        nestedPlanningDir,
        specSlug: 'nested-spec',
        status: 'done',
      );

      final file = File(
        '$nestedPlanningDir/nested-spec/sdlc/sdlc-flow-state.json',
      );
      expect(file.existsSync(), isTrue);
    });

    test('overwriting with a second call replaces content correctly', () async {
      await writeFixtureFlowState(
        tempDir.path,
        specSlug: '8B-workflow-done',
        status: 'running',
      );
      await writeFixtureFlowState(
        tempDir.path,
        specSlug: '8B-workflow-done',
        status: 'done',
        pr: 'https://example/pr/2',
      );

      final file = File(
        '${tempDir.path}/8B-workflow-done/sdlc/sdlc-flow-state.json',
      );
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['status'], 'done');
      expect(decoded['pr'], 'https://example/pr/2');
    });
  });
}
