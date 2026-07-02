// Widget tests for SessionsListScreen + SessionCard.
//
// Overrides `sessionsProvider` and `needsInputProvider` directly with fake
// StateNotifiers (no real socket/API involved) so these tests exercise only
// the rendering + badge logic — mirrors the override style already used by
// `connection_banner_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/state/events_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';
import 'package:bastion_ui/widgets/session_card.dart';

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionsListScreen', () {
    testWidgets('renders one card per session with correct badges', (
      tester,
    ) async {
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
    });

    testWidgets('shows empty state when there are no sessions', (tester) async {
      await tester.pumpWidget(_buildScreen(sessions: const []));
      await tester.pump();

      expect(find.byType(SessionCard), findsNothing);
      expect(find.text('No active sessions'), findsOneWidget);
    });

    testWidgets('needs-input flag badge appears for a flagged session', (
      tester,
    ) async {
      const sessions = [
        SessionDto(name: 'alpha', state: 'running'),
        SessionDto(name: 'beta', state: 'running'),
      ];

      await tester.pumpWidget(
        _buildScreen(sessions: sessions, needsInput: const {'beta'}),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    });

    testWidgets('needs-input flag clears when the event stream updates', (
      tester,
    ) async {
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

    testWidgets('tapping a card navigates toward the session detail route', (
      tester,
    ) async {
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
    });
  });
}
