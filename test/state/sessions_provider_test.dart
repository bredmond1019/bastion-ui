// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/sessions_provider.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors reconnect_test.dart / api_test.dart fixtures)
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

  /// Simulate a server-side disconnect (a clean stream close) so the
  /// [BastionSocket] schedules a reconnect.
  void drop() {
    if (!_controller.isClosed) _controller.close();
  }

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

/// Pump the microtask/timer queue so async work (handshake, seed fetch,
/// frame decoding) settles.
///
/// Uses a real (non-zero) delay per round so rxdart's `.debounceTime(~150ms)`
/// on the provider-layer WS stream (see `lib/state/sessions_provider.dart`)
/// has enough wall-clock time to fire within the default 5 rounds (200ms
/// total).
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Build a connected [BastionSocket] backed by a [FakeWsTransport].
///
/// [transports] (optional) collects every transport the socket creates —
/// including replacement transports created on a drop+reconnect — so
/// reconnect-focused tests can reach the *next* fake transport after
/// [FakeWsTransport.drop].
Future<(BastionSocket, FakeWsTransport)> makeConnectedSocket({
  List<FakeWsTransport>? transports,
  Duration Function(int attempt)? backoffSchedule,
}) async {
  final ts = transports ?? <FakeWsTransport>[];
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    backoffSchedule: backoffSchedule,
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      ts.add(t);
      return t;
    },
  );
  socket.connect();
  await pump();
  ts.single.completeReady();
  await pump();
  return (socket, ts.single);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('bastionSocketProvider / bastionApiProvider — unset guards', () {
    test('bastionSocketProvider/bastionApiProvider default to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(bastionSocketProvider), isNull);
      expect(container.read(bastionApiProvider), isNull);
    });

    test('sessionsProvider throws StateError when read before connect', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container.read(sessionsProvider),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('sessionsProvider', () {
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

    test('subscribes to the "sessions" topic on first read', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: <Map<String, dynamic>>[],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(sessionsProvider);
      await pump();

      expect(transport.sent, [
        jsonEncode(ClientFrames.subscribe(sessionsTopic)),
      ]);
    });

    test('seeds state from REST getSessions() before any WS frame', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {'name': 'alpha', 'state': 'running', 'last_line': r'$ '},
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(sessionsProvider);
      await pump();

      final sessions = container.read(sessionsProvider);
      expect(sessions, hasLength(1));
      expect(sessions.single.name, 'alpha');
      expect(sessions.single.state, 'running');
    });

    test('applies a WS "sessions" frame snapshot over the REST seed', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {'name': 'stale', 'state': 'idle'},
        ],
      );
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      container.read(sessionsProvider);
      await pump();
      expect(container.read(sessionsProvider).single.name, 'stale');

      transport.addMessage(
        jsonEncode({
          'kind': 'sessions',
          'payload': {
            'sessions': [
              {'name': 'fresh-a', 'state': 'running'},
              {'name': 'fresh-b', 'state': 'blocked'},
            ],
          },
        }),
      );
      await pump();

      final sessions = container.read(sessionsProvider);
      expect(sessions.map((s) => s.name), ['fresh-a', 'fresh-b']);
    });

    test(
      'a slow REST seed never overwrites a WS snapshot that already arrived',
      () async {
        final seedCompleter = Completer<({int statusCode, String body})>();
        final slowHttp = _SlowHttpTransport(seedCompleter.future);
        final slowApi = BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: slowHttp,
        );
        container = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => slowApi),
          ],
        );

        container.read(sessionsProvider);
        await pump();

        // WS snapshot arrives first, before the REST seed resolves.
        transport.addMessage(
          jsonEncode({
            'kind': 'sessions',
            'payload': {
              'sessions': [
                {'name': 'live', 'state': 'running'},
              ],
            },
          }),
        );
        await pump();
        expect(container.read(sessionsProvider).single.name, 'live');

        // Now let the slow REST seed resolve with a stale snapshot.
        seedCompleter.complete((
          statusCode: 200,
          body: jsonEncode([
            {'name': 'stale', 'state': 'idle'},
          ]),
        ));
        await pump();

        expect(container.read(sessionsProvider).single.name, 'live');
      },
    );

    test('sends "unsubscribe" for the "sessions" topic on dispose', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: <Map<String, dynamic>>[],
      );
      // Local, test-owned container so it can be disposed inline without
      // conflicting with the shared `tearDown`'s dispose of `container`.
      final localContainer = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );

      localContainer.read(sessionsProvider);
      await pump();
      localContainer.dispose();

      expect(
        transport.sent,
        contains(jsonEncode(ClientFrames.unsubscribe(sessionsTopic))),
      );

      // Satisfy tearDown's container.dispose() with a fresh, undisposed
      // container (the shared `container` field was never assigned above).
      container = ProviderContainer();
    });

    test(
      'a reconnect re-runs the REST seed (second getSessions() call)',
      () async {
        // This test needs its own socket (zero backoff, and access to every
        // transport it creates) rather than the shared `setUp` socket, so it
        // builds and disposes both inline.
        final reconnectTransports = <FakeWsTransport>[];
        final (reconnectSocket, firstTransport) = await makeConnectedSocket(
          transports: reconnectTransports,
          backoffSchedule: (_) => Duration.zero,
        );

        httpTransport.setResponse(
          statusCode: 200,
          body: [
            {'name': 'first-seed', 'state': 'running'},
          ],
        );
        final localContainer = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => reconnectSocket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
        );
        localContainer.read(sessionsProvider);
        await pump();
        expect(httpTransport.getCallCount, 1);

        // Drop → the socket reconnects (zero backoff) → the notifier's
        // status-stream listener sees the transition into `connected` again
        // and re-runs `_seed()`.
        httpTransport.setResponse(
          statusCode: 200,
          body: [
            {'name': 'reseeded', 'state': 'idle'},
          ],
        );
        firstTransport.drop();
        await pump();
        expect(
          reconnectTransports,
          hasLength(2),
          reason: 'a replacement transport should exist after the drop',
        );
        reconnectTransports[1].completeReady();
        await pump();

        expect(httpTransport.getCallCount, 2);
        expect(localContainer.read(sessionsProvider).single.name, 'reseeded');

        localContainer.dispose();
        await reconnectSocket.dispose();
      },
    );

    test(
      're-seed after a reconnect does not clobber a newer WS snapshot',
      () async {
        final reconnectTransports = <FakeWsTransport>[];
        final (reconnectSocket, firstTransport) = await makeConnectedSocket(
          transports: reconnectTransports,
          backoffSchedule: (_) => Duration.zero,
        );

        // Drop → reconnect: the slow REST re-seed is queued but not yet
        // resolved.
        final seedCompleter = Completer<({int statusCode, String body})>();
        final slowHttp = _SlowHttpTransport(seedCompleter.future);
        final slowApi = BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: slowHttp,
        );
        final slowContainer = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => reconnectSocket),
            bastionApiProvider.overrideWith((ref) => slowApi),
          ],
        );
        slowContainer.read(sessionsProvider);
        await pump();

        firstTransport.drop();
        await pump();
        expect(reconnectTransports, hasLength(2));
        reconnectTransports[1].completeReady();
        await pump();

        // A newer WS snapshot arrives before the slow re-seed resolves.
        reconnectTransports[1].addMessage(
          jsonEncode({
            'kind': 'sessions',
            'payload': {
              'sessions': [
                {'name': 'live-after-reconnect', 'state': 'running'},
              ],
            },
          }),
        );
        await pump();
        expect(
          slowContainer.read(sessionsProvider).single.name,
          'live-after-reconnect',
        );

        // The slow re-seed (triggered by the reconnect) now resolves with a
        // stale snapshot — it must not overwrite the newer WS state.
        seedCompleter.complete((
          statusCode: 200,
          body: jsonEncode([
            {'name': 'stale-reseed', 'state': 'idle'},
          ]),
        ));
        await pump();
        expect(
          slowContainer.read(sessionsProvider).single.name,
          'live-after-reconnect',
        );

        slowContainer.dispose();
        await reconnectSocket.dispose();
      },
    );
  });
}

/// [HttpTransport] whose GET response resolves only when [future] completes
/// — used to simulate a REST seed that is slower than the first WS frame.
class _SlowHttpTransport implements HttpTransport {
  _SlowHttpTransport(this.future);

  final Future<({int statusCode, String body})> future;

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) => future;

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
