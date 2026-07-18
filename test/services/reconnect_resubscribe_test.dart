// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Fake transport (mirrors test/services/reconnect_test.dart's pattern)
// ---------------------------------------------------------------------------

/// In-memory [WsTransport] for unit tests.
///
/// Controls:
/// - [completeReady] — simulate a successful WS handshake.
/// - [failReady] — simulate a handshake error (e.g. 401 or refused).
/// - [drop] — close the stream cleanly (simulates a server-side disconnect).
class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void failReady(Object error, [StackTrace? st]) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, st);
    }
  }

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pump the Dart event / microtask queue [rounds] times.
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

BastionSocket makeSocket(
  List<FakeWsTransport> transports, {
  Duration Function(int)? backoff,
}) {
  return BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = FakeWsTransport();
      transports.add(t);
      return t;
    },
    backoffSchedule: backoff ?? (_) => Duration.zero,
  );
}

/// Decode the topic name of a `subscribe`/`unsubscribe` frame, or null if
/// [raw] isn't one of those.
String? subscribeTopic(String raw, {required String kind}) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  if (json['kind'] != kind) return null;
  final payload = json['payload'] as Map<String, dynamic>;
  return payload['topic'] as String?;
}

void main() {
  group('active-subscription replay on reconnect', () {
    test(
      'replays subscribe frames for every active topic after a reconnect',
      () async {
        final transports = <FakeWsTransport>[];
        final socket = makeSocket(transports);

        socket.connect();
        transports[0].completeReady();
        await pump();
        expect(transports, hasLength(1));

        socket.send(ClientFrames.subscribe('sessions'));
        socket.send(ClientFrames.subscribe('pane:alpha'));

        // The first connect's own explicit subscribes were sent once.
        expect(transports[0].sent, hasLength(2));

        // Drop → reconnect.
        transports[0].drop();
        await pump();
        expect(
          transports,
          hasLength(2),
          reason: 'a new transport should have been created for the reconnect',
        );
        transports[1].completeReady();
        await pump();

        // The replay should have re-sent a subscribe for both topics, in
        // deterministic (insertion) order — and nothing else.
        expect(transports[1].sent, hasLength(2));
        expect(
          subscribeTopic(transports[1].sent[0], kind: 'subscribe'),
          'sessions',
        );
        expect(
          subscribeTopic(transports[1].sent[1], kind: 'subscribe'),
          'pane:alpha',
        );

        await socket.dispose();
      },
    );

    test('does not replay anything on the very first connect', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);

      socket.connect();
      transports[0].completeReady();
      await pump();

      // Nothing was subscribed yet, and no replay should happen on this
      // (first) connect regardless.
      expect(transports[0].sent, isEmpty);

      await socket.dispose();
    });

    test('a topic unsubscribed before the drop is not replayed', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);

      socket.connect();
      transports[0].completeReady();
      await pump();

      socket.send(ClientFrames.subscribe('sessions'));
      socket.send(ClientFrames.subscribe('pane:alpha'));
      socket.send(ClientFrames.unsubscribe('sessions'));

      // Drop → reconnect.
      transports[0].drop();
      await pump();
      transports[1].completeReady();
      await pump();

      // Only the still-active topic ("pane:alpha") should be replayed.
      expect(transports[1].sent, hasLength(1));
      expect(
        subscribeTopic(transports[1].sent[0], kind: 'subscribe'),
        'pane:alpha',
      );

      await socket.dispose();
    });

    test('replay is idempotent/safe when the registry is empty', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);

      socket.connect();
      transports[0].completeReady();
      await pump();

      // No subscriptions were ever sent.

      // Drop → reconnect.
      transports[0].drop();
      await pump();
      transports[1].completeReady();
      await pump();

      expect(transports[1].sent, isEmpty);

      await socket.dispose();
    });

    test('no provider torn down/rebuilt — the socket instance survives the '
        'reconnect and the frame/status streams keep working', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      transports[0].completeReady();
      await pump();
      socket.send(ClientFrames.subscribe('sessions'));

      transports[0].drop();
      await pump();
      transports[1].completeReady();
      await pump();

      expect(socket.status, ConnectionStatus.connected);
      expect(
        statuses,
        containsAllInOrder([
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
          ConnectionStatus.reconnecting,
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
        ]),
      );

      await socket.dispose();
    });
  });
}
