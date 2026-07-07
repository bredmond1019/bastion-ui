// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/events_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionSocketProvider;

// ---------------------------------------------------------------------------
// Fake transport (mirrors pane_provider_test.dart / sessions_provider_test.dart)
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

/// Build a connected [BastionSocket] backed by a [FakeWsTransport], driven
/// entirely by [async] (a [FakeAsync] controller) so no real wall-clock time
/// elapses.
(BastionSocket, FakeWsTransport) makeConnectedSocket(FakeAsync async) {
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
  async.flushMicrotasks();
  transports.single.completeReady();
  async.flushMicrotasks();
  return (socket, transports.single);
}

String sessionsFrameJson(List<String> names) => jsonEncode({
  'kind': 'sessions',
  'payload': {
    'sessions': names.map((n) => {'name': n, 'state': 'idle'}).toList(),
  },
});

String eventFrameJson({required String session, required String event}) =>
    jsonEncode({
      'kind': 'event',
      'payload': {'session': session, 'event': event},
    });

void main() {
  group('high-frequency state-refresh streams (rxdart .debounceTime)', () {
    test('a rapid burst of frames within the debounce window coalesces to a '
        'single latest emission', () {
      fakeAsync((async) {
        final (socket, transport) = makeConnectedSocket(async);
        addTearDown(() => socket.dispose());

        // Mirrors the exact production pattern used in
        // sessions_provider.dart / pane_provider.dart / workflows_provider.dart:
        // filter to the frame kind of interest, then debounce (trailing,
        // ~150ms) before a provider would consume it.
        final emissions = <SessionsFrame>[];
        final sub = socket.frames
            .where((f) => f is SessionsFrame)
            .cast<SessionsFrame>()
            .debounceTime(const Duration(milliseconds: 150))
            .listen(emissions.add);
        addTearDown(sub.cancel);

        // Burst of 5 rapid frames, each 10ms apart (well within the 150ms
        // debounce window).
        for (var i = 0; i < 5; i++) {
          transport.addMessage(sessionsFrameJson(['session-$i']));
          async.elapse(const Duration(milliseconds: 10));
        }
        // Let the debounce window elapse fully after the last frame.
        async.elapse(const Duration(milliseconds: 200));

        expect(
          emissions.length,
          1,
          reason: 'the burst must coalesce to a single emission',
        );
        expect(
          emissions.single.sessions.single.name,
          'session-4',
          reason: 'the single emission must carry the latest value',
        );
      });
    });

    test('events spaced beyond the window each emit individually', () {
      fakeAsync((async) {
        final (socket, transport) = makeConnectedSocket(async);
        addTearDown(() => socket.dispose());

        final emissions = <SessionsFrame>[];
        final sub = socket.frames
            .where((f) => f is SessionsFrame)
            .cast<SessionsFrame>()
            .debounceTime(const Duration(milliseconds: 150))
            .listen(emissions.add);
        addTearDown(sub.cancel);

        // A single isolated event still emits (after the window).
        transport.addMessage(sessionsFrameJson(['solo']));
        async.elapse(const Duration(milliseconds: 200));
        expect(emissions.length, 1);

        // A second event, spaced well beyond the debounce window, emits on
        // its own too — it is not merged with the first.
        transport.addMessage(sessionsFrameJson(['second']));
        async.elapse(const Duration(milliseconds: 200));
        expect(emissions.length, 2);

        expect(emissions[0].sessions.single.name, 'solo');
        expect(emissions[1].sessions.single.name, 'second');
      });
    });
  });

  group('needsInputEventsProvider stays undebounced', () {
    test('every needs_input event is delivered, even in a rapid burst', () {
      fakeAsync((async) {
        final (socket, transport) = makeConnectedSocket(async);
        addTearDown(() => socket.dispose());

        final container = ProviderContainer(
          overrides: [bastionSocketProvider.overrideWith((ref) => socket)],
        );
        addTearDown(container.dispose);

        final received = <EventFrame>[];
        final sub = container
            .read(needsInputEventsProvider)
            .listen(received.add);
        addTearDown(sub.cancel);

        // A rapid burst of needs_input events, each well within what would
        // be a 150ms debounce window if this stream were (wrongly) coalesced.
        for (var i = 0; i < 5; i++) {
          transport.addMessage(
            eventFrameJson(session: 'session-$i', event: needsInputEvent),
          );
          async.elapse(const Duration(milliseconds: 10));
        }
        async.flushMicrotasks();

        expect(
          received.length,
          5,
          reason:
              'the prompt stream must never coalesce/drop events — every '
              'needs_input must be delivered exactly once',
        );
        expect(received.map((f) => f.session).toList(), [
          'session-0',
          'session-1',
          'session-2',
          'session-3',
          'session-4',
        ]);
      });
    });
  });
}
