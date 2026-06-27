// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Fake transport (no real network)
// ---------------------------------------------------------------------------

/// In-memory [WsTransport] for unit tests.
///
/// Controls:
/// - [completeReady] — simulate a successful WS handshake.
/// - [failReady] — simulate a handshake error (e.g. 401 or refused).
/// - [addMessage] — push a text frame from the server.
/// - [drop] — close the stream cleanly (simulates a server-side disconnect).
/// - [errorStream] — push an error into the stream.
class FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  // ---- Test helpers -------------------------------------------------------

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void failReady(Object error, [StackTrace? st]) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, st);
    }
  }

  void addMessage(String msg) => _controller.add(msg);

  /// Simulate a clean disconnect (server closes).
  void drop() {
    if (!_controller.isClosed) _controller.close();
  }

  /// Simulate an error on the stream.
  void errorStream(Object error) => _controller.addError(error);

  // ---- WsTransport --------------------------------------------------------

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
///
/// Each round awaits a zero-duration future, draining microtasks +
/// scheduled timers with zero delay.
Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Build a [BastionSocket] with injected transport factory.
///
/// [transports] is populated with each [FakeWsTransport] as it is created
/// (one per connection attempt).
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Backoff schedule (static, pure — no network)
  // -------------------------------------------------------------------------
  group('BastionSocket.computeBackoff — exponential with cap', () {
    test('starts at 1 s', () {
      expect(BastionSocket.computeBackoff(0), const Duration(seconds: 1));
    });

    test('doubles on each attempt', () {
      expect(BastionSocket.computeBackoff(1), const Duration(seconds: 2));
      expect(BastionSocket.computeBackoff(2), const Duration(seconds: 4));
      expect(BastionSocket.computeBackoff(3), const Duration(seconds: 8));
      expect(BastionSocket.computeBackoff(4), const Duration(seconds: 16));
    });

    test('caps at 32 s at attempt 5', () {
      expect(BastionSocket.computeBackoff(5), const Duration(seconds: 32));
    });

    test('remains capped beyond attempt 5', () {
      expect(BastionSocket.computeBackoff(6), const Duration(seconds: 32));
      expect(BastionSocket.computeBackoff(10), const Duration(seconds: 32));
      expect(BastionSocket.computeBackoff(100), const Duration(seconds: 32));
    });
  });

  // -------------------------------------------------------------------------
  // Status transitions
  // -------------------------------------------------------------------------
  group('status transitions', () {
    test(
      'disconnected → connecting → connected on first successful connect',
      () async {
        final transports = <FakeWsTransport>[];
        final socket = makeSocket(transports);
        final statuses = <ConnectionStatus>[];
        socket.statusStream.listen(statuses.add);

        // connect() emits 'connecting' synchronously, then awaits transport.ready
        socket.connect();
        expect(statuses, [ConnectionStatus.connecting]);
        expect(transports, hasLength(1));

        // Simulate successful handshake
        transports[0].completeReady();
        await pump();

        expect(statuses, [
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
        ]);
        expect(socket.status, ConnectionStatus.connected);

        await socket.dispose();
      },
    );

    test('connected → reconnecting → connecting after a clean drop', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      transports[0].completeReady();
      await pump();
      expect(socket.status, ConnectionStatus.connected);

      // Drop the first connection
      transports[0].drop();
      await pump();

      expect(
        statuses,
        containsAllInOrder([
          ConnectionStatus.connecting,
          ConnectionStatus.connected,
          ConnectionStatus.reconnecting,
          ConnectionStatus.connecting, // second attempt
        ]),
      );

      await socket.dispose();
    });

    test('reconnect fires and completes on drop', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      transports[0].completeReady();
      await pump();
      expect(socket.status, ConnectionStatus.connected);

      // Drop → reconnect
      transports[0].drop();
      await pump(); // reconnect timer fires + second _doConnect starts

      // Complete the second handshake
      expect(
        transports,
        hasLength(2),
        reason: 'a new transport should have been created for the reconnect',
      );
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

    test('fatal auth failure stops reconnect and sets isFatalAuth', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final statuses = <ConnectionStatus>[];
      socket.statusStream.listen(statuses.add);

      socket.connect();
      expect(transports, hasLength(1));

      // Simulate 401 on handshake
      transports[0].failReady(Exception('WebSocket upgrade failed: 401'));
      await pump();

      expect(socket.isFatalAuth, isTrue);
      expect(socket.status, ConnectionStatus.disconnected);
      // No further transport should have been created
      expect(transports, hasLength(1));

      // Calling connect again is a no-op after fatal auth
      socket.connect();
      await pump();
      expect(transports, hasLength(1));

      await socket.dispose();
    });

    test('auth error on stream is fatal', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);

      socket.connect();
      transports[0].completeReady();
      await pump();
      expect(socket.status, ConnectionStatus.connected);

      // Push an unauthorized error through the stream
      transports[0].errorStream(Exception('unauthorized'));
      await pump();

      expect(socket.isFatalAuth, isTrue);
      expect(socket.status, ConnectionStatus.disconnected);
      // Should not have created a new transport
      expect(transports, hasLength(1));

      await socket.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Backoff attempt counter
  // -------------------------------------------------------------------------
  group('backoff attempt counter', () {
    test('resets to 0 after a successful connect', () async {
      final transports = <FakeWsTransport>[];
      final attempts = <int>[];
      final socket = makeSocket(
        transports,
        backoff: (a) {
          attempts.add(a);
          return Duration.zero;
        },
      );

      // First connect → no backoff called
      socket.connect();
      transports[0].completeReady();
      await pump();
      expect(socket.status, ConnectionStatus.connected);

      // Drop → backoff called with 0 (first reconnect after reset)
      transports[0].drop();
      await pump();
      expect(attempts, [0]);

      // Complete the reconnect
      transports[1].completeReady();
      await pump();
      expect(socket.status, ConnectionStatus.connected);

      // Drop again → backoff called with 0 again (reset after second success)
      transports[1].drop();
      await pump();
      expect(attempts, [0, 0]);

      await socket.dispose();
    });

    test('increments on consecutive failed handshakes', () async {
      final transports = <FakeWsTransport>[];
      final attempts = <int>[];
      final socket = makeSocket(
        transports,
        backoff: (a) {
          attempts.add(a);
          return Duration.zero;
        },
      );

      // First connect + successful handshake
      socket.connect();
      transports[0].completeReady();
      await pump();

      // Drop → reconnect attempt 1
      transports[0].drop();
      await pump(); // backoff(0) called; transports[1] created
      // Fail the second handshake (non-auth)
      transports[1].failReady(Exception('connection refused'));
      await pump(); // backoff(1) called; transports[2] created
      // Fail the third handshake
      transports[2].failReady(Exception('connection refused'));
      await pump(); // backoff(2) called; transports[3] created

      expect(attempts, [0, 1, 2]);

      await socket.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Frame decoding
  // -------------------------------------------------------------------------
  group('frame stream', () {
    test('delivers decoded BastionFrames to the frames stream', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final frames = <dynamic>[];
      socket.frames.listen(frames.add);

      socket.connect();
      transports[0].completeReady();
      await pump();

      transports[0].addMessage('{"kind":"echo","payload":{"msg":"hello"}}');
      await pump();

      expect(frames, hasLength(1));
      expect(frames[0].runtimeType.toString(), contains('Echo'));

      await socket.dispose();
    });

    test('delivers MalformedFrame for non-JSON messages', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);
      final frames = <dynamic>[];
      socket.frames.listen(frames.add);

      socket.connect();
      transports[0].completeReady();
      await pump();

      transports[0].addMessage('not-json{{{');
      await pump();

      expect(frames, hasLength(1));
      expect(frames[0].runtimeType.toString(), contains('Malformed'));

      await socket.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Dispose safety
  // -------------------------------------------------------------------------
  group('dispose', () {
    test('connect after dispose is a no-op', () async {
      final transports = <FakeWsTransport>[];
      final socket = makeSocket(transports);

      socket.connect();
      transports[0].completeReady();
      await pump();

      await socket.dispose();

      // Should not create a new transport
      socket.connect();
      await pump();
      expect(transports, hasLength(1));
    });
  });
}
