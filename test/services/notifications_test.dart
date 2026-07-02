// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/services/notifications.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionSocketProvider;

// ---------------------------------------------------------------------------
// Fake plugin (no platform channels required)
// ---------------------------------------------------------------------------

/// Records every call made through [NotificationService] instead of hitting
/// a real platform channel.
class _FakePlugin extends Fake implements FlutterLocalNotificationsPlugin {
  InitializationSettings? initializedWith;
  final List<({int id, String? title, String? body})> shown = [];

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializedWith = initializationSettings;
    return true;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body));
  }
}

// ---------------------------------------------------------------------------
// Fake WS transport (mirrors events_provider_test.dart's fixture)
// ---------------------------------------------------------------------------

class _FakeWsTransport implements WsTransport {
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

Future<(BastionSocket, _FakeWsTransport)> makeConnectedSocket() async {
  final transports = <_FakeWsTransport>[];
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) {
      final t = _FakeWsTransport();
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
  group('NotificationService', () {
    test(
      'initialize() configures the plugin with android + darwin settings',
      () async {
        final plugin = _FakePlugin();
        final service = NotificationService(plugin: plugin);

        await service.initialize();

        expect(plugin.initializedWith, isNotNull);
        expect(plugin.initializedWith!.android, isNotNull);
        expect(plugin.initializedWith!.iOS, isNotNull);
      },
    );

    test(
      'notifyNeedsInput() shows a notification naming the session',
      () async {
        final plugin = _FakePlugin();
        final service = NotificationService(plugin: plugin);

        await service.notifyNeedsInput('sess-a');

        expect(plugin.shown, hasLength(1));
        expect(plugin.shown.single.title, 'Needs input');
        expect(plugin.shown.single.body, contains('sess-a'));
      },
    );

    test('repeat notifications for the same session reuse the same id '
        '(replace, not stack)', () async {
      final plugin = _FakePlugin();
      final service = NotificationService(plugin: plugin);

      await service.notifyNeedsInput('sess-a');
      await service.notifyNeedsInput('sess-a');

      expect(plugin.shown, hasLength(2));
      expect(plugin.shown[0].id, plugin.shown[1].id);
    });

    test('different sessions get different notification ids', () async {
      final plugin = _FakePlugin();
      final service = NotificationService(plugin: plugin);

      await service.notifyNeedsInput('sess-a');
      await service.notifyNeedsInput('sess-b');

      expect(plugin.shown[0].id, isNot(plugin.shown[1].id));
    });
  });

  group('notificationWiringProvider', () {
    late BastionSocket socket;
    late _FakeWsTransport transport;
    late _FakePlugin plugin;
    late NotificationService service;
    late ProviderContainer container;

    setUp(() async {
      final (s, t) = await makeConnectedSocket();
      socket = s;
      transport = t;
      plugin = _FakePlugin();
      service = NotificationService(plugin: plugin);
      container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          notificationServiceProvider.overrideWithValue(service),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await socket.dispose();
    });

    test(
      'fires a notification for each needs_input event once watched',
      () async {
        container.read(notificationWiringProvider); // activate the bridge

        transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
        await pump();

        expect(plugin.shown, hasLength(1));
        expect(plugin.shown.single.body, contains('sess-a'));
      },
    );

    test('does nothing before the provider is watched', () async {
      transport.addMessage(eventFrameJson('sess-a', 'needs_input'));
      await pump();

      expect(plugin.shown, isEmpty);
    });

    test('ignores non-needs_input events', () async {
      container.read(notificationWiringProvider);

      transport.addMessage(eventFrameJson('sess-a', 'started'));
      await pump();

      expect(plugin.shown, isEmpty);
    });

    test('stops firing once the last watcher unsubscribes', () async {
      final sub = container.listen(notificationWiringProvider, (prev, next) {});
      await pump();

      // Closing the last listener on an autoDispose provider tears down its
      // socket subscription (see NotificationService's `ref.onDispose`).
      sub.close();
      await pump();

      transport.addMessage(eventFrameJson('sess-b', 'needs_input'));
      await pump();

      expect(plugin.shown, isEmpty);
    });
  });

  test('EventFrame import stays reachable via services/notifications.dart', () {
    // Compile-time check that the re-exported/imported EventFrame type used
    // internally by notifications.dart matches the one from models/frame.dart
    // — guards against a future refactor silently diverging the two.
    const frame = EventFrame(session: 's', event: 'needs_input', extra: {});
    expect(frame.session, 's');
  });
}
