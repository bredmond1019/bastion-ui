// Widget tests for main.dart's app-shell wiring.
//
// Guards bugs found during BU.1.A close-out, extended in BU.2.A Task 7:
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
//   3. (BU.2.A) DashboardScreen must be reachable the same way, and tapping
//      a repo row must push RepoDetailScreen via the same route-generation
//      mechanism (`/repos/{name}`) — this is the task that closes the loop
//      BU.1.A initially missed, applied to the dashboard/repo-detail pair.
//   4. (BU.3.A Task 6) QuickActionsScreen must be reachable as a third
//      bottom-nav destination alongside Sessions/Dashboard.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/main.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/screens/quick_actions_screen.dart';
import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/theme/tokens.dart';

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

/// Serves `getSessions` -> one session named `alpha`, `getPane` -> a
/// one-line buffer, and `getRepos`/`getRepoStatus`/`getRepoHandoff`/
/// `getRepoWorkflows` -> one repo named `bastion-ui` with no handoff and no
/// in-flight workflows, so the sessions, dashboard, and repo-detail screens
/// all have content.
class _FakeHttpTransport implements HttpTransport {
  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('/pane')) {
      return (statusCode: 200, body: '{"session_name":"alpha","lines":["hi"]}');
    }
    if (url.contains('/repos/') && url.endsWith('/status')) {
      return (
        statusCode: 200,
        body:
            '{"name":"bastion-ui","now":"wiring dashboard","next":"","'
            'blocked":"","has_handoff":false,"momentum_now":"","'
            'momentum_next":"","momentum_blocked":"","momentum_improve":"",'
            '"momentum_recurring":""}',
      );
    }
    if (url.contains('/repos/') && url.endsWith('/handoff')) {
      return (statusCode: 404, body: '{"code":"C002"}');
    }
    if (url.contains('/repos/') && url.endsWith('/workflows')) {
      return (statusCode: 200, body: '[]');
    }
    if (url.endsWith('/api/repos')) {
      return (
        statusCode: 200,
        body:
            '[{"name":"bastion-ui","now":"wiring dashboard","has_handoff":false}]',
      );
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

/// In-memory fake for `secureStorageProvider` (mirrors
/// `commands_provider_test.dart`) — avoids `FlutterSecureStorage` platform
/// channels so `QuickActionsScreen`'s `commandsProvider` can load/persist
/// during a widget test.
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];
}

/// Reproduces `_ConnectedBody`'s three-tab bottom-nav structure. That class
/// is library-private to `main.dart` (and, unlike sockets/APIs, has no
/// fake-injectable seam), so it cannot be pumped directly from this file —
/// this harness drives the identical tab widgets
/// (`SessionsListScreen`/`DashboardScreen`/`QuickActionsScreen`) and
/// `NavigationDestination` set that `main.dart`'s `_ConnectedBodyState.build`
/// wires up, to exercise the real tab-selection wiring without going through
/// `HomeShell`'s real (non-fake-injectable) socket lifecycle — which would
/// leave a pending reconnect `Timer` at test teardown (see
/// `bastion_socket.dart`'s `_scheduleReconnect`).
class _TabsHarness extends StatefulWidget {
  const _TabsHarness();

  @override
  State<_TabsHarness> createState() => _TabsHarnessState();
}

class _TabsHarnessState extends State<_TabsHarness> {
  static const _tabs = [
    SessionsListScreen(),
    DashboardScreen(),
    QuickActionsScreen(),
  ];

  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Sessions'),
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.flash_on), label: 'Actions'),
        ],
      ),
    );
  }
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
  if (name != null && name.startsWith('/repos/')) {
    final repoName = Uri.decodeComponent(name.substring('/repos/'.length));
    return MaterialPageRoute<void>(
      builder: (_) => RepoDetailScreen(repoName: repoName),
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
    'renders dark regardless of the host platform brightness (BU.10.A '
    'Task 5) — this is the assertion that would have caught the stock '
    'Material-light baseline this block exists to fix',
    (tester) async {
      // Force the ambient platform brightness to light. If BastionApp still
      // wired `themeMode: ThemeMode.system` (or a light `theme:`), the
      // rendered Scaffold would pick up a light background here.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionProvider.overrideWith((_) => _DisconnectedNotifier()),
          ],
          child: const BastionApp(),
        ),
      );
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
      expect(materialApp.darkTheme, isNull);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      final resolvedBackground =
          scaffold.backgroundColor ??
          Theme.of(
            tester.element(find.byType(Scaffold).first),
          ).scaffoldBackgroundColor;
      expect(resolvedBackground, AppTokens.paper);
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
            theme: AppTheme.dark,
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

  testWidgets('DashboardScreen and a pushed RepoDetailScreen both see the live '
      'socket/API set on the root ProviderScope (BU.2.A Task 7)', (
    tester,
  ) async {
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
          theme: AppTheme.dark,
          home: const DashboardScreen(),
          onGenerateRoute: _generateRoute,
        ),
      ),
    );
    await tester.pump();

    // The dashboard screen itself is reachable and REST-seeded.
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('bastion-ui'), findsOneWidget);

    // Tapping the repo row pushes RepoDetailScreen via the app's
    // Navigator — a route this test builds outside DashboardScreen's own
    // widget tree, exactly as BastionApp's Navigator sits above
    // HomeShell.
    await tester.tap(find.text('bastion-ui'));
    await tester.pumpAndSettle();

    // If bastionSocketProvider/bastionApiProvider weren't visible to the
    // pushed route, workflowsProvider/repoHandoffProvider would throw a
    // StateError here.
    expect(tester.takeException(), isNull);
    expect(find.text('bastion-ui'), findsWidgets); // detail AppBar title
    expect(find.text('wiring dashboard'), findsOneWidget); // status "now"
  });

  testWidgets('quick-actions tab is present, selectable, and renders '
      'QuickActionsScreen (BU.3.A Task 6)', (tester) async {
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
    final fakeStorage = _FakeSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
          secureStorageProvider.overrideWithValue(fakeStorage),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const _TabsHarness(),
          onGenerateRoute: _generateRoute,
        ),
      ),
    );
    await tester.pump();

    // Sessions is the initial tab; the other two destinations (including
    // the new "Actions" quick-actions tab) are present but not selected.
    expect(find.text('Sessions'), findsWidgets); // tab label + AppBar
    expect(find.text('Dashboard'), findsOneWidget); // nav label only
    expect(find.text('Actions'), findsOneWidget); // nav label only

    // Selecting the quick-actions destination renders QuickActionsScreen.
    await tester.tap(find.text('Actions'));
    await tester.pump();

    expect(find.byType(QuickActionsScreen), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget); // AppBar title
  });

  testWidgets(
    'tablet-width composition renders exactly one embedded detail pane, no '
    'push-navigated duplicate (BU.4.A Task 6)',
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

      // Pin the test surface to a tablet width (>= ResponsiveScaffold's
      // breakpoint) so SessionsListScreen renders its list+detail split.
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const _TabsHarness(),
            onGenerateRoute: _generateRoute,
          ),
        ),
      );
      await tester.pump();

      // Tapping the session card selects it into the split-view detail pane
      // (tablet width) rather than pushing a route.
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      // Exactly one SessionDetailScreen — the embedded split-pane instance
      // — must exist; if the app also pushed a route on top (the
      // double-render this test guards against), a second instance would
      // appear on the Navigator stack.
      expect(find.byType(SessionDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
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
