// Reachability test for RunsScreen (`BU.13.E` task 3).
//
// This repo has shipped unreachable UI twice with a fully green suite:
// `BU.1.A` (a screen built and unit-tested but never routed to from the
// running app) and `ticket-brand-header-lockup` (a widget placed in
// `ResponsiveScaffold`, used only as a `body:`, so it rendered below the
// real app bar on one tab and not at all on the others). The lesson both
// times: assert reachability BY NAVIGATION from `HomeShell`, never mere
// presence in the widget tree. Mirrors
// `test/screens/briefing_reachable_test.dart`'s pattern.
//
// `HomeShell`'s real `_ConnectedBody` opens a real, non-fake-injectable
// `BastionSocket` from `_HomeShellState._initSocket` (see
// `main_wiring_test.dart`'s `_TabsHarness` doc comment) — pumping the real
// `HomeShell` with a configured connection would open a live WebSocket
// connection attempt and leave a pending reconnect `Timer` at test
// teardown. So, like `main_wiring_test.dart`'s existing tab tests, this
// file drives the identical tab widgets and `NavigationDestination` set
// that `main.dart`'s `_ConnectedBodyState.build` wires up — the real
// tab-selection wiring — with `bastionSocketProvider`/`bastionApiProvider`
// overridden to fakes on the root `ProviderScope`, exactly as `HomeShell`
// itself publishes them (D2: root-scope, not a nested override), so every
// tab (including `SessionsListScreen`, which all five tabs' shared
// `IndexedStack` builds eagerly regardless of which is selected) can read
// them without throwing.

import 'dart:async';

import 'package:bastion_ui/screens/briefing_screen.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/screens/quick_actions_screen.dart';
import 'package:bastion_ui/screens/runs_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider, bastionSocketProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes — no real network / platform channels (mirrors main_wiring_test.dart)
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

/// Seeds one session (`alpha`) and one repo (`bastion-ui`) so
/// `SessionsListScreen`/`DashboardScreen` — both built eagerly inside the
/// shared `IndexedStack` regardless of which tab is selected — have content
/// rather than throwing on an unregistered route.
FakeHttpTransport _makeHttpTransport() {
  final t = FakeHttpTransport();
  t.on(
    'GET',
    '/api/sessions',
    status: 200,
    body: [
      {'name': 'alpha', 'state': 'running'},
    ],
  );
  t.on(
    'GET',
    '/api/sessions/alpha/pane',
    status: 200,
    body: {
      'session_name': 'alpha',
      'lines': ['hi'],
    },
  );
  t.on(
    'GET',
    '/api/repos',
    status: 200,
    body: [
      {'name': 'bastion-ui', 'now': 'wiring runs', 'has_handoff': false},
    ],
  );
  t.on(
    'GET',
    '/api/repos/bastion-ui/status',
    status: 200,
    body: {
      'name': 'bastion-ui',
      'now': 'wiring runs',
      'next': '',
      'blocked': '',
      'has_handoff': false,
      'momentum_now': '',
      'momentum_next': '',
      'momentum_blocked': '',
      'momentum_improve': '',
      'momentum_recurring': '',
    },
  );
  t.on(
    'GET',
    '/api/repos/bastion-ui/handoff',
    status: 404,
    body: {'code': 'C002'},
  );
  t.on(
    'GET',
    '/api/repos/bastion-ui/workflows',
    status: 200,
    body: <dynamic>[],
  );
  t.on(
    'GET',
    '/api/board',
    status: 200,
    body: {
      'scope': 'hq',
      'lanes': <String, dynamic>{},
      'repos': [
        {
          'repo': 'bastion-ui',
          'lanes': {
            'now': [
              {'id': 'BU.13.E', 'title': 'Wiring runs', 'repo': 'bastion-ui'},
            ],
          },
        },
      ],
      'stale': false,
    },
  );
  return t;
}

/// Reproduces `_ConnectedBody`'s real tab list and bottom-nav wiring from
/// `main.dart`'s `_ConnectedBodyState.build`, post `BU.13.E` task 3:
/// Briefing, Sessions, Dashboard, Actions, then Runs.
class _TabsHarness extends StatefulWidget {
  const _TabsHarness();

  @override
  State<_TabsHarness> createState() => _TabsHarnessState();
}

class _TabsHarnessState extends State<_TabsHarness> {
  static const _tabs = [
    BriefingScreen(),
    SessionsListScreen(),
    DashboardScreen(),
    QuickActionsScreen(),
    RunsScreen(),
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
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Briefing',
          ),
          NavigationDestination(icon: Icon(Icons.list), label: 'Sessions'),
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.flash_on), label: 'Actions'),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            label: 'Runs',
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'tapping the Runs destination navigates to RunsScreen (BU.13.E task 3)',
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
        transport: _makeHttpTransport(),
      );
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bastionSocketProvider.overrideWith((ref) => socket),
            bastionApiProvider.overrideWith((ref) => api),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const _TabsHarness()),
        ),
      );
      await tester.pump();

      // Runs is not selected by default — Briefing (index 0) is.
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

      // Tapping the Runs destination is the assertion that would have
      // caught a lockup-style miss: the destination existing in the nav
      // bar is not the same as tapping it actually rendering the screen.
      await tester.tap(find.text('Runs'));
      await tester.pump();

      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
        4,
        reason: 'tapping Runs must navigate to it, index 4',
      );
      expect(find.byType(RunsScreen), findsOneWidget);
      expect(find.text('Runs'), findsWidgets); // nav label + AppBar title
      expect(tester.takeException(), isNull);
    },
  );
}
