// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/pane_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors sessions_provider_test.dart / api_test.dart fixtures)
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

/// Pump the microtask/timer queue so async work (handshake, seed fetch,
/// frame decoding) settles.
///
/// Uses a real (non-zero) delay per round so rxdart's `.debounceTime(~150ms)`
/// on the provider-layer WS streams (see `lib/state/pane_provider.dart`) has
/// enough wall-clock time to fire within the default 5 rounds (200ms total).
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
  group('paneProvider', () {
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
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await socket.dispose();
    });

    test('subscribes to "pane:<name>" on first watch', () async {
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      expect(transport.sent, [
        jsonEncode(ClientFrames.subscribe(paneTopic('alpha'))),
      ]);
    });

    test('seeds the buffer from REST getPane() before any WS frame', () async {
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {
          'session_name': 'alpha',
          'lines': [r'$ ls', 'foo.txt'],
        },
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      expect(container.read(paneProvider('alpha')), [r'$ ls', 'foo.txt']);
    });

    test('applies a WS "pane" frame over the REST seed', () async {
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {
          'session_name': 'alpha',
          'lines': ['stale'],
        },
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();
      expect(container.read(paneProvider('alpha')), ['stale']);

      transport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 1,
            'lines': ['fresh-a', 'fresh-b'],
          },
        }),
      );
      await pump();

      expect(container.read(paneProvider('alpha')), ['fresh-a', 'fresh-b']);
    });

    test('drops an out-of-order/duplicate frame (seq <= last seq)', () async {
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      transport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 5,
            'lines': ['at-seq-5'],
          },
        }),
      );
      await pump();
      expect(container.read(paneProvider('alpha')), ['at-seq-5']);

      // Duplicate seq.
      transport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 5,
            'lines': ['duplicate'],
          },
        }),
      );
      // Out-of-order (lower) seq.
      transport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 3,
            'lines': ['stale-out-of-order'],
          },
        }),
      );
      await pump();

      expect(container.read(paneProvider('alpha')), ['at-seq-5']);
    });

    test('ignores "pane" frames for a different session', () async {
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      transport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'beta',
            'seq': 1,
            'lines': ['not-for-alpha'],
          },
        }),
      );
      await pump();

      expect(container.read(paneProvider('alpha')), <String>[]);
    });

    test(
      'a slow REST seed never overwrites a WS frame that already arrived',
      () async {
        final seedCompleter = Completer<({int statusCode, String body})>();
        final slowHttp = _SlowHttpTransport(seedCompleter.future);
        final slowApi = BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: slowHttp,
        );
        final localContainer = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => slowApi),
          ],
        );
        addTearDown(localContainer.dispose);

        localContainer.listen(paneProvider('alpha'), (_, _) {});
        await pump();

        // WS frame arrives first, before the REST seed resolves.
        transport.addMessage(
          jsonEncode({
            'kind': 'pane',
            'payload': {
              'session': 'alpha',
              'seq': 1,
              'lines': ['live'],
            },
          }),
        );
        await pump();
        expect(localContainer.read(paneProvider('alpha')), ['live']);

        // Now let the slow REST seed resolve with a stale snapshot.
        seedCompleter.complete((
          statusCode: 200,
          body: jsonEncode({
            'session_name': 'alpha',
            'lines': ['stale'],
          }),
        ));
        await pump();

        expect(localContainer.read(paneProvider('alpha')), ['live']);
      },
    );

    test(
      'sends "unsubscribe" for "pane:<name>" when the last watcher disposes',
      () async {
        httpTransport.on(
          'GET',
          '/api/sessions/alpha/pane',
          status: 200,
          body: {'session_name': 'alpha', 'lines': <String>[]},
        );
        final localContainer = ProviderContainer(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
        );

        final sub = localContainer.listen(paneProvider('alpha'), (_, _) {});
        await pump();
        sub.close();
        localContainer.dispose();
        await pump();

        expect(
          transport.sent,
          contains(jsonEncode(ClientFrames.unsubscribe(paneTopic('alpha')))),
        );
      },
    );

    test('a reconnect re-runs the REST seed (second getPane() call)', () async {
      // This test needs its own socket (zero backoff, and access to every
      // transport it creates) rather than the shared `setUp` socket, so it
      // builds and disposes both inline.
      final reconnectTransports = <FakeWsTransport>[];
      final (reconnectSocket, firstTransport) = await makeConnectedSocket(
        transports: reconnectTransports,
        backoffSchedule: (_) => Duration.zero,
      );

      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {
          'session_name': 'alpha',
          'lines': ['first-seed'],
        },
      );
      final localContainer = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => reconnectSocket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      localContainer.listen(paneProvider('alpha'), (_, _) {});
      await pump();
      expect(httpTransport.callCount('GET', '/api/sessions/alpha/pane'), 1);

      // Drop → the socket reconnects (zero backoff) → the notifier's
      // status-stream listener sees the transition into `connected` again
      // and re-runs `_seed()`.
      httpTransport.on(
        'GET',
        '/api/sessions/alpha/pane',
        status: 200,
        body: {
          'session_name': 'alpha',
          'lines': ['reseeded'],
        },
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

      expect(httpTransport.callCount('GET', '/api/sessions/alpha/pane'), 2);
      expect(localContainer.read(paneProvider('alpha')), ['reseeded']);

      localContainer.dispose();
      await reconnectSocket.dispose();
    });

    test('re-seed after a reconnect does not clobber a newer WS frame or reset '
        'seq ordering', () async {
      final reconnectTransports = <FakeWsTransport>[];
      final (reconnectSocket, firstTransport) = await makeConnectedSocket(
        transports: reconnectTransports,
        backoffSchedule: (_) => Duration.zero,
      );

      // The REST seed is wired to a slow transport for the whole test so
      // both the initial seed and the reconnect-triggered re-seed can be
      // held pending until asserted against.
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
      slowContainer.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      // A WS pane frame arrives before the drop, establishing `_lastSeq`
      // and setting `_sawWsFrame` (so the still-pending initial seed can
      // never clobber it).
      firstTransport.addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 5,
            'lines': ['at-seq-5'],
          },
        }),
      );
      await pump();
      expect(slowContainer.read(paneProvider('alpha')), ['at-seq-5']);

      // Drop → reconnect: the notifier's status-stream listener re-runs
      // `_seed()`, which is still pending on the same slow completer.
      firstTransport.drop();
      await pump();
      expect(reconnectTransports, hasLength(2));
      reconnectTransports[1].completeReady();
      await pump();

      // A newer WS pane frame (higher seq) arrives before the slow
      // re-seed resolves.
      reconnectTransports[1].addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 6,
            'lines': ['live-after-reconnect'],
          },
        }),
      );
      await pump();
      expect(slowContainer.read(paneProvider('alpha')), [
        'live-after-reconnect',
      ]);

      // The slow seed(s) (initial + reconnect re-seed) now resolve with a
      // stale buffer — they must not overwrite the newer WS state.
      seedCompleter.complete((
        statusCode: 200,
        body: jsonEncode({
          'session_name': 'alpha',
          'lines': ['stale-reseed'],
        }),
      ));
      await pump();
      expect(slowContainer.read(paneProvider('alpha')), [
        'live-after-reconnect',
      ]);

      // A subsequent frame with a lower seq than the pre-drop high-water
      // mark must still be dropped as out-of-order — the reconnect must
      // not have reset `_lastSeq`.
      reconnectTransports[1].addMessage(
        jsonEncode({
          'kind': 'pane',
          'payload': {
            'session': 'alpha',
            'seq': 5,
            'lines': ['stale-out-of-order'],
          },
        }),
      );
      await pump();
      expect(slowContainer.read(paneProvider('alpha')), [
        'live-after-reconnect',
      ]);

      slowContainer.dispose();
      await reconnectSocket.dispose();
    });
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
