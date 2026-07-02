// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/events_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionSocketProvider;

// ---------------------------------------------------------------------------
// Fake transport (mirrors reconnect_test.dart's fixture)
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

Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
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

String eventFrameJson(String session, String event) => jsonEncode({
  'kind': 'event',
  'payload': {'session': session, 'event': event},
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late BastionSocket socket;
  late FakeWsTransport transport;
  late ProviderContainer container;

  setUp(() async {
    final (s, t) = await makeConnectedSocket();
    socket = s;
    transport = t;
    container = ProviderContainer(
      overrides: [bastionSocketProvider.overrideWith((ref) => socket)],
    );
  });

  tearDown(() async {
    container.dispose();
    await socket.dispose();
  });

  group('needsInputEventsProvider', () {
    test(
      'emits only "needs_input" events, ignoring other event kinds',
      () async {
        final received = <EventFrame>[];
        final sub = container
            .read(needsInputEventsProvider)
            .listen(received.add);
        addTearDown(sub.cancel);

        transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
        transport.addMessage(eventFrameJson('sess-b', 'started'));
        transport.addMessage(eventFrameJson('sess-c', 'needs_input'));
        await pump();

        expect(received.map((f) => f.session), ['sess-a', 'sess-c']);
        expect(received.every((f) => f.event == 'needs_input'), isTrue);
      },
    );

    test('ignores non-event frame kinds (e.g. sessions)', () async {
      final received = <EventFrame>[];
      final sub = container.read(needsInputEventsProvider).listen(received.add);
      addTearDown(sub.cancel);

      transport.addMessage(
        jsonEncode({
          'kind': 'sessions',
          'payload': {'sessions': <Map<String, dynamic>>[]},
        }),
      );
      await pump();

      expect(received, isEmpty);
    });
  });

  group('needsInputProvider', () {
    test('flags a session on its first "needs_input" event', () async {
      container.read(needsInputProvider); // force provider creation
      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      await pump();

      expect(container.read(needsInputProvider), {'sess-a'});
    });

    test('accumulates distinct sessions across events', () async {
      container.read(needsInputProvider);
      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      transport.addMessage(eventFrameJson('sess-b', 'needs_input'));
      await pump();

      expect(container.read(needsInputProvider), {'sess-a', 'sess-b'});
    });

    test('clear() removes a flagged session', () async {
      container.read(needsInputProvider);
      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      await pump();
      expect(container.read(needsInputProvider), {'sess-a'});

      container.read(needsInputProvider.notifier).clear('sess-a');

      expect(container.read(needsInputProvider), isEmpty);
    });

    test('clear() on an unflagged session is a no-op', () async {
      container.read(needsInputProvider);
      container.read(needsInputProvider.notifier).clear('never-flagged');

      expect(container.read(needsInputProvider), isEmpty);
    });

    test('ignores non-"needs_input" event kinds', () async {
      container.read(needsInputProvider);
      transport.addMessage(eventFrameJson('sess-a', 'started'));
      transport.addMessage(eventFrameJson('sess-a', 'stopped'));
      await pump();

      expect(container.read(needsInputProvider), isEmpty);
    });

    test('a second "needs_input" event for the same session (re-blocked '
        'cycle) keeps it flagged', () async {
      container.read(needsInputProvider);
      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      await pump();
      container.read(needsInputProvider.notifier).clear('sess-a');
      expect(container.read(needsInputProvider), isEmpty);

      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      await pump();

      expect(container.read(needsInputProvider), {'sess-a'});
    });
  });
}
