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
/// on the provider-layer WS streams (see `lib/state/pane_provider.dart`) has
/// enough wall-clock time to fire within the default 5 rounds (200ms total).
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Build a connected [BastionSocket] backed by a [FakeWsTransport].
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
      httpTransport.setResponse(
        statusCode: 200,
        body: {'session_name': 'alpha', 'lines': <String>[]},
      );

      container.listen(paneProvider('alpha'), (_, _) {});
      await pump();

      expect(transport.sent, [
        jsonEncode(ClientFrames.subscribe(paneTopic('alpha'))),
      ]);
    });

    test('seeds the buffer from REST getPane() before any WS frame', () async {
      httpTransport.setResponse(
        statusCode: 200,
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
      httpTransport.setResponse(
        statusCode: 200,
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
      httpTransport.setResponse(
        statusCode: 200,
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
      httpTransport.setResponse(
        statusCode: 200,
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
        httpTransport.setResponse(
          statusCode: 200,
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
