// Widget tests for main.dart's app-shell wiring — specifically that once a
// socket/API pair is available, HomeShell's body actually reaches
// SessionsListScreen (the bug this file guards: BU.1.A's screens existed and
// were unit-tested in isolation, but nothing routed to them from the running
// app).

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/main.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';

// ---------------------------------------------------------------------------
// Fakes (no real network / platform channels)
// ---------------------------------------------------------------------------

class _FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();

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

class _FakeHttpTransport implements HttpTransport {
  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async => (statusCode: 200, body: '[]');

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async => (statusCode: 204, body: '');

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async => (statusCode: 204, body: '');
}

void main() {
  testWidgets(
    'HomeShell shows a placeholder when no connection is configured',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionProvider.overrideWith((_) => _DisconnectedNotifier()),
          ],
          child: const BastionApp(),
        ),
      );
      await tester.pump();

      expect(find.text('Configure a connection in Settings'), findsOneWidget);
      expect(find.text('Sessions'), findsNothing);
    },
  );

  testWidgets(
    'ConnectedSessionsBody reaches SessionsListScreen once socket/API are live',
    (tester) async {
      final socket = BastionSocket(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transportFactory: (uri, {headers}) => _FakeWsTransport(),
      );
      addTearDown(socket.dispose);
      final api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: _FakeHttpTransport(),
      );
      addTearDown(api.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectedSessionsBody(socket: socket, api: api),
        ),
      );
      await tester.pump();

      // SessionsListScreen's own AppBar title — proves the connected body
      // actually renders the sessions list, not a placeholder.
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('No active sessions'), findsOneWidget);
    },
  );
}

/// Minimal notifier seeded to disconnected/unconfigured state — avoids
/// FlutterSecureStorage platform-channel calls (mirrors `widget_test.dart`).
class _DisconnectedNotifier extends StateNotifier<ConnectionState>
    implements ConnectionNotifier {
  _DisconnectedNotifier()
    : super(
        const ConnectionState(
          config: ConnectionConfig.defaultConfig,
          status: ConnectionStatus.disconnected,
        ),
      );

  @override
  Future<void> saveConfig({
    required String host,
    required int port,
    required String token,
  }) async {}

  @override
  Future<String?> readToken() async => null;

  @override
  void updateStatus(ConnectionStatus status) {
    state = state.copyWith(status: status);
  }
}
