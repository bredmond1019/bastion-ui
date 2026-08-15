// Widget tests for SessionsListScreen + SessionCard.
//
// Overrides `sessionsProvider` and `needsInputProvider` directly with fake
// StateNotifiers (no real socket/API involved) so these tests exercise only
// the rendering + badge logic — mirrors the override style already used by
// `connection_banner_test.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/events_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/widgets/session_card.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSessionsNotifier extends StateNotifier<List<SessionDto>>
    implements SessionsNotifier {
  _FakeSessionsNotifier(super.state);
}

class _FakeNeedsInputNotifier extends StateNotifier<Set<String>>
    implements NeedsInputNotifier {
  _FakeNeedsInputNotifier(super.state);

  @override
  void clear(String session) {
    if (!state.contains(session)) return;
    state = {...state}..remove(session);
  }
}

/// Never-connects WS transport (mirrors `main_wiring_test.dart`'s
/// `_FakeWsTransport`) so `paneProvider`'s live-subscription half has a
/// [bastionSocketProvider] to read without touching a real network.
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

/// Builds a [FakeHttpTransport] that serves `getPane` -> a one-line buffer
/// for `alpha`, so an embedded `SessionDetailScreen` (tablet split pane) has
/// content and no live network/socket is touched. The two tests that use
/// this only ever open the `alpha` session, so only that route is
/// registered.
FakeHttpTransport _buildFakeHttpTransport() {
  final transport = FakeHttpTransport();
  transport.on(
    'GET',
    '/api/sessions/alpha/pane',
    status: 200,
    body: {
      'session_name': 'alpha',
      'lines': ['hi'],
    },
  );
  return transport;
}

Widget _buildScreen({
  required List<SessionDto> sessions,
  Set<String> needsInput = const {},
}) {
  return ProviderScope(
    overrides: [
      sessionsProvider.overrideWith((ref) => _FakeSessionsNotifier(sessions)),
      needsInputProvider.overrideWith(
        (ref) => _FakeNeedsInputNotifier(needsInput),
      ),
    ],
    child: const MaterialApp(home: SessionsListScreen()),
  );
}

/// Pins the test surface to a phone width (below the tablet breakpoint) so
/// `ResponsiveScaffold.isWide` is false — deterministic regardless of the
/// default test surface size. Resets on teardown.
void _setPhoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pins the test surface to a tablet width (at/above the breakpoint) so
/// `ResponsiveScaffold.isWide` is true. Resets on teardown.
void _setTabletWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionsListScreen', () {
    testWidgets('renders one card per session with correct badges', (
      tester,
    ) async {
      _setPhoneWidth(tester);
      const sessions = [
        SessionDto(name: 'alpha', state: 'running', lastLine: r'$ build'),
        SessionDto(name: 'beta', state: 'idle', lastLine: r'$ '),
      ];

      await tester.pumpWidget(_buildScreen(sessions: sessions));
      await tester.pump();

      expect(find.byType(SessionCard), findsNWidgets(2));
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active), findsNothing);

      // Running/idle dots resolve their colour from StatusTones, not a
      // literal hex value (BU.10.A task 6).
      final tones = StatusTones.dark;
      final avatars = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .toList();
      expect(avatars[0].backgroundColor, tones.active.foreground);
      expect(avatars[1].backgroundColor, tones.neutral.foreground);
    });

    testWidgets('shows empty state when there are no sessions', (tester) async {
      _setPhoneWidth(tester);
      await tester.pumpWidget(_buildScreen(sessions: const []));
      await tester.pump();

      expect(find.byType(SessionCard), findsNothing);
      expect(find.text('No active sessions'), findsOneWidget);
    });

    testWidgets('needs-input flag badge appears for a flagged session', (
      tester,
    ) async {
      _setPhoneWidth(tester);
      const sessions = [
        SessionDto(name: 'alpha', state: 'running'),
        SessionDto(name: 'beta', state: 'running'),
      ];

      await tester.pumpWidget(
        _buildScreen(sessions: sessions, needsInput: const {'beta'}),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.notifications_active));
      expect(icon.color, StatusTones.dark.warning.foreground);
    });

    testWidgets('needs-input flag clears when the event stream updates', (
      tester,
    ) async {
      _setPhoneWidth(tester);
      const sessions = [SessionDto(name: 'alpha', state: 'running')];
      final notifier = _FakeNeedsInputNotifier({'alpha'});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(
              (ref) => _FakeSessionsNotifier(sessions),
            ),
            needsInputProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(home: SessionsListScreen()),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active), findsOneWidget);

      notifier.clear('alpha');
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active), findsNothing);
    });

    testWidgets(
      'phone width: opening a flagged session and popping back clears its '
      'badge in the list (BU.ticket.needs-input-badge-clear)',
      (tester) async {
        _setPhoneWidth(tester);
        const sessions = [SessionDto(name: 'alpha', state: 'running')];
        final api = BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: _buildFakeHttpTransport(),
        );
        addTearDown(api.dispose);
        final socket = BastionSocket(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transportFactory: (uri, {headers}) => _FakeWsTransport(),
        );
        addTearDown(socket.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionsProvider.overrideWith(
                (ref) => _FakeSessionsNotifier(sessions),
              ),
              // Real needsInputProvider (not the fake) so the detail
              // screen's `clear()` call is the one actually observed by
              // the list's badge — this is the operator-visible outcome
              // the ticket is about, not just the provider mechanism.
              needsInputProvider.overrideWith(
                (ref) => NeedsInputNotifier(const Stream.empty()),
              ),
              bastionApiProvider.overrideWith((ref) => api),
              bastionSocketProvider.overrideWith((ref) => socket),
            ],
            child: MaterialApp(
              home: const SessionsListScreen(),
              onGenerateRoute: (settings) {
                if (settings.name == sessionDetailRouteName('alpha')) {
                  return MaterialPageRoute<void>(
                    builder: (_) =>
                        const SessionDetailScreen(sessionName: 'alpha'),
                  );
                }
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('detail')),
                );
              },
            ),
          ),
        );
        await tester.pump();

        // Flag alpha directly through the provider (simulating an already
        // arrived needs_input event) and confirm the badge shows.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionsListScreen)),
        );
        container.read(needsInputProvider.notifier).state = {'alpha'};
        await tester.pump();
        expect(find.byIcon(Icons.notifications_active), findsOneWidget);

        // Push the detail route by tapping the card.
        await tester.tap(find.byType(SessionCard));
        await tester.pumpAndSettle();
        expect(find.byType(SessionDetailScreen), findsOneWidget);
        expect(container.read(needsInputProvider), isEmpty);

        // Pop back to the list — the badge must be gone.
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.pop();
        await tester.pumpAndSettle();

        expect(find.byType(SessionsListScreen), findsOneWidget);
        expect(find.byIcon(Icons.notifications_active), findsNothing);
      },
    );

    testWidgets(
      'phone width: tapping a card navigates toward the session detail '
      'route',
      (tester) async {
        _setPhoneWidth(tester);
        const sessions = [SessionDto(name: 'alpha', state: 'running')];
        String? pushedRoute;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionsProvider.overrideWith(
                (ref) => _FakeSessionsNotifier(sessions),
              ),
              needsInputProvider.overrideWith(
                (ref) => _FakeNeedsInputNotifier(const {}),
              ),
            ],
            child: MaterialApp(
              home: const SessionsListScreen(),
              onGenerateRoute: (settings) {
                pushedRoute = settings.name;
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('detail')),
                );
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(SessionCard));
        await tester.pumpAndSettle();

        expect(pushedRoute, sessionDetailRouteName('alpha'));
        // No inline detail pane at phone width.
        expect(find.byType(SessionDetailScreen), findsNothing);
      },
    );

    testWidgets(
      'tablet width: selecting a session renders it in the split detail '
      'pane without pushing a route (BU.4.A)',
      (tester) async {
        _setTabletWidth(tester);
        const sessions = [
          SessionDto(name: 'alpha', state: 'running'),
          SessionDto(name: 'beta', state: 'idle'),
        ];
        String? pushedRoute;
        final api = BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: _buildFakeHttpTransport(),
        );
        addTearDown(api.dispose);
        final socket = BastionSocket(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transportFactory: (uri, {headers}) => _FakeWsTransport(),
        );
        addTearDown(socket.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionsProvider.overrideWith(
                (ref) => _FakeSessionsNotifier(sessions),
              ),
              needsInputProvider.overrideWith(
                (ref) => _FakeNeedsInputNotifier(const {}),
              ),
              bastionApiProvider.overrideWith((ref) => api),
              bastionSocketProvider.overrideWith((ref) => socket),
            ],
            child: MaterialApp(
              home: const SessionsListScreen(),
              onGenerateRoute: (settings) {
                pushedRoute = settings.name;
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('detail')),
                );
              },
            ),
          ),
        );
        await tester.pump();

        // Both the list and the empty-selection placeholder render, side
        // by side, before any selection.
        expect(find.byType(SessionCard), findsNWidgets(2));
        expect(find.text('Select a session'), findsOneWidget);
        expect(find.byType(SessionDetailScreen), findsNothing);

        await tester.tap(find.byType(SessionCard).first);
        await tester.pumpAndSettle();

        // The detail pane now shows the selected session inline, and no
        // route was pushed.
        expect(find.byType(SessionDetailScreen), findsOneWidget);
        expect(find.text('Select a session'), findsNothing);
        expect(pushedRoute, isNull);
        // The list is still visible alongside the detail pane.
        expect(find.byType(SessionCard), findsNWidgets(2));
      },
    );
  });
}
