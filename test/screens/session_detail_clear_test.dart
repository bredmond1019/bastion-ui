// Widget tests for SessionDetailScreen's needs_input badge clearing.
//
// Task 2 scope: the tablet split-view case, where Flutter reuses the same
// State object across a session switch (`didUpdateWidget` fires, not
// `initState`). Task 3 adds the pushed-route / scoping / no-op / exception
// coverage below.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/events_provider.dart' show needsInputProvider;
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors session_detail_test.dart's fixtures)
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

/// Registers a `GET .../pane` route for [session] that echoes it back,
/// mirroring what the old local `FakeHttpTransport.get()` computed
/// dynamically from the request URL.
void registerPane(FakeHttpTransport transport, String session) {
  transport.on(
    'GET',
    '/api/sessions/$session/pane',
    status: 200,
    body: {'session_name': session, 'lines': <String>[]},
  );
}

String eventFrameJson(String session, String event) => jsonEncode({
  'kind': 'event',
  'payload': {'session': session, 'event': event},
});

Future<void> pump(WidgetTester tester, [int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<(BastionSocket, FakeWsTransport)> makeConnectedSocket(
  WidgetTester tester,
) async {
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
  await pump(tester);
  transports.single.completeReady();
  await pump(tester);
  return (socket, transports.single);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionDetailScreen needs_input clearing (embedded/tablet)', () {
    late BastionSocket socket;
    late FakeWsTransport wsTransport;
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer container;

    setUp(() {
      httpTransport = FakeHttpTransport();
      registerPane(httpTransport, 'alpha');
      registerPane(httpTransport, 'beta');
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

    testWidgets('switching the embedded session (no remount) clears the '
        'newly-selected session and leaves the old one alone', (tester) async {
      final (s, t) = await makeConnectedSocket(tester);
      socket = s;
      wsTransport = t;
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      // Force-initialize the notifier so its event subscription is live
      // before pushing WS messages — it's created lazily on first read.
      container.read(needsInputProvider);

      // Flag both sessions before the screen ever mounts.
      wsTransport.addMessage(eventFrameJson('alpha', 'needs_input'));
      wsTransport.addMessage(eventFrameJson('beta', 'needs_input'));
      await pump(tester);
      expect(container.read(needsInputProvider), {'alpha', 'beta'});

      // Mount embedded on 'alpha' — initState clears it.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SessionDetailScreen(sessionName: 'alpha', embedded: true),
          ),
        ),
      );
      await pump(tester);

      expect(container.read(needsInputProvider), {'beta'});

      // Rebuild the SAME element tree with a different sessionName — this
      // is what the tablet split view does when the operator taps a
      // different row (`selectedSessionProvider` changes, the widget in
      // `responsive_scaffold.dart`'s detail pane slot updates in place).
      // Same widget type, same slot, no Key change => State is reused and
      // `didUpdateWidget` fires instead of `initState`.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SessionDetailScreen(sessionName: 'beta', embedded: true),
          ),
        ),
      );
      await pump(tester);

      expect(
        container.read(needsInputProvider),
        isEmpty,
        reason:
            'beta must clear via didUpdateWidget on the reused State — '
            'a bug here would leave beta flagged since initState does '
            'not run again for a reused State object.',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SessionDetailScreen needs_input clearing (pushed route / phone)', () {
    late BastionSocket socket;
    late FakeWsTransport wsTransport;
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer container;

    setUp(() {
      httpTransport = FakeHttpTransport();
      registerPane(httpTransport, 'alpha');
      registerPane(httpTransport, 'beta');
      registerPane(httpTransport, 'gamma');
      registerPane(httpTransport, 'never-flagged');
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

    Future<void> mountFor(
      WidgetTester tester, {
      required Set<String> flag,
    }) async {
      final (s, t) = await makeConnectedSocket(tester);
      socket = s;
      wsTransport = t;
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      container.read(needsInputProvider);
      for (final session in flag) {
        wsTransport.addMessage(eventFrameJson(session, 'needs_input'));
      }
      await pump(tester);
    }

    testWidgets('opening a flagged session via the pushed route clears only '
        'that session', (tester) async {
      await mountFor(tester, flag: {'alpha', 'gamma'});
      expect(container.read(needsInputProvider), {'alpha', 'gamma'});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SessionDetailScreen(sessionName: 'alpha'),
          ),
        ),
      );
      await pump(tester);

      expect(
        container.read(needsInputProvider),
        {'gamma'},
        reason:
            'clearing must be scoped to the opened session only — gamma '
            'keeps its flag.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a never-flagged session is a no-op and does not '
        'throw', (tester) async {
      await mountFor(tester, flag: {'beta'});
      expect(container.read(needsInputProvider), {'beta'});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SessionDetailScreen(sessionName: 'never-flagged'),
          ),
        ),
      );
      await pump(tester);

      expect(
        container.read(needsInputProvider),
        {'beta'},
        reason: 'a session that was never flagged clears nothing else.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no riverpod modify-during-build exception is raised when '
        'the screen opens with a flagged session', (tester) async {
      await mountFor(tester, flag: {'alpha'});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SessionDetailScreen(sessionName: 'alpha'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(container.read(needsInputProvider), isEmpty);
    });
  });
}
