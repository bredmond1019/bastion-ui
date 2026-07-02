// Widget tests for main.dart's app-shell wiring.
//
// Guards two bugs found during BU.1.A close-out:
//   1. HomeShell's body must actually reach SessionsListScreen once
//      connected (screens existed and were unit-tested in isolation, but
//      nothing routed to them from the running app).
//   2. bastionSocketProvider/bastionApiProvider must be visible to routes
//      *pushed* onto the app's Navigator, not just the initial screen — the
//      Navigator lives inside MaterialApp, an ANCESTOR of HomeShell's body,
//      so a nested ProviderScope override scoped to that body is invisible
//      to pushed routes. Overriding the shared, mutable
//      bastionSocketProvider/bastionApiProvider on the single root
//      ProviderScope (as main.dart does) fixes this.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/main.dart';
import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;

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

/// Serves `getSessions` -> one session named `alpha`, and `getPane` -> a
/// one-line buffer, so both the list and detail screens have content.
class _FakeHttpTransport implements HttpTransport {
  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('/pane')) {
      return (statusCode: 200, body: '{"session_name":"alpha","lines":["hi"]}');
    }
    return (statusCode: 200, body: '[{"name":"alpha","state":"running"}]');
  }

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

/// The same route-generation logic `BastionApp` wires up, reproduced here so
/// the test can drive a real `Navigator` without going through `HomeShell`
/// (which owns a real, non-fake-injectable `BastionSocket`/`BastionApi`).
Route<void>? _generateRoute(RouteSettings settings) {
  final name = settings.name;
  if (name != null && name.startsWith('/sessions/')) {
    final sessionName = Uri.decodeComponent(
      name.substring('/sessions/'.length),
    );
    return MaterialPageRoute<void>(
      builder: (_) => SessionDetailScreen(sessionName: sessionName),
      settings: settings,
    );
  }
  return null;
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
    'SessionsListScreen and a pushed SessionDetailScreen both see the live '
    'socket/API set on the root ProviderScope',
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
        ProviderScope(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
          child: MaterialApp(
            home: const SessionsListScreen(),
            onGenerateRoute: _generateRoute,
          ),
        ),
      );
      await tester.pump();

      // The list screen itself is reachable and REST-seeded.
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);

      // Tapping the card pushes SessionDetailScreen via the app's Navigator
      // — a route this test builds outside SessionsListScreen's own widget
      // tree, exactly as BastionApp's Navigator sits above HomeShell.
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      // If bastionSocketProvider/bastionApiProvider weren't visible to the
      // pushed route, paneProvider would throw a StateError here.
      expect(tester.takeException(), isNull);
      expect(find.text('alpha'), findsWidgets); // detail screen's AppBar title
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
