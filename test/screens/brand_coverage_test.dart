// Coverage sweep test for `BU.10.C` task 6.
//
// This is the gated, repeatable version of the block's headline acceptance
// criterion ("every screen is assembled from brand parts") — it pumps each
// of the six re-skinned screens and asserts at least one primitive from
// `lib/widgets/brand/` is present in its widget tree. Before this test the
// criterion was only verifiable by a one-time human read of the diff; now a
// future regression (a screen quietly reverting to a bare Card/Container)
// fails CI.
//
// Fakes/build helpers below mirror each screen's own widget test file
// (`dashboard_test.dart`, `repo_detail_test.dart`, `quick_actions_test.dart`,
// `session_detail_test.dart`, `sessions_list_test.dart`) trimmed to the
// minimum wiring needed to render without touching a real socket/API/secure
// storage platform channel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/screens/quick_actions_screen.dart';
import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/screens/session_detail_screen.dart';
import 'package:bastion_ui/screens/sessions_list_screen.dart';
import 'package:bastion_ui/screens/settings_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show secureStorageProvider;
import 'package:bastion_ui/state/events_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart';
import 'package:bastion_ui/state/workflows_provider.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Shared fakes (mirror the per-screen test files' fixtures)
// ---------------------------------------------------------------------------

class _FakeSessionsNotifier extends StateNotifier<List<SessionDto>>
    implements SessionsNotifier {
  _FakeSessionsNotifier(super.state);
}

class _FakeNeedsInputNotifier extends StateNotifier<Set<String>>
    implements NeedsInputNotifier {
  _FakeNeedsInputNotifier(super.state);

  @override
  void clear(String session) {}
}

class _FakeRepoWorkflowsNotifier extends StateNotifier<RepoWorkflowsState>
    implements RepoWorkflowsNotifier {
  _FakeRepoWorkflowsNotifier(super.state, {required this.repoName});

  @override
  final String repoName;
}

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
  }) async {
    return _store[key];
  }
}

class _FakeWsTransport implements WsTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final _readyCompleter = Completer<void>();

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

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

typedef RecordedCall = ({String method, String url, String? body});

final class _FakeHttpTransport implements HttpTransport {
  final List<RecordedCall> calls = [];

  ({int statusCode, String body}) _consume() => (statusCode: 204, body: '');

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'GET', url: url, body: null));
    return _consume();
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add((method: 'POST', url: url, body: body));
    return _consume();
  }

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: 'DELETE', url: url, body: null));
    return _consume();
  }
}

/// A widget matcher for "at least one brand primitive is present" — any one
/// of the six `lib/widgets/brand/` exports counts.
Finder _anyBrandPrimitive() => find.byWidgetPredicate(
  (widget) =>
      widget is PanelCard ||
      widget is GradientTopBar ||
      widget is IconTile ||
      widget is Eyebrow ||
      widget is HeadingRule ||
      widget is StatusPill,
);

Future<void> _expectBrandPrimitivePresent(WidgetTester tester) async {
  expect(
    _anyBrandPrimitive(),
    findsWidgets,
    reason: 'expected at least one brand/ primitive in the widget tree',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Brand coverage sweep (BU.10.C task 6)', () {
    testWidgets('SessionsListScreen renders a brand primitive', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsProvider.overrideWith(
              (ref) => _FakeSessionsNotifier(const [
                SessionDto(name: 'alpha', state: 'running'),
              ]),
            ),
            needsInputProvider.overrideWith(
              (ref) => _FakeNeedsInputNotifier(const {}),
            ),
          ],
          child: const MaterialApp(home: SessionsListScreen()),
        ),
      );
      await tester.pump();

      await _expectBrandPrimitivePresent(tester);
    });

    testWidgets('SessionDetailScreen renders a brand primitive', (
      tester,
    ) async {
      final wsTransport = _FakeWsTransport();
      final socket = BastionSocket(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transportFactory: (uri, {headers}) => wsTransport,
      );
      socket.connect();
      await tester.pump(const Duration(milliseconds: 40));
      wsTransport.completeReady();
      await tester.pump(const Duration(milliseconds: 40));

      final api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: _FakeHttpTransport(),
      );

      final container = ProviderContainer(
        overrides: [
          bastionSocketProvider.overrideWith((ref) => socket),
          bastionApiProvider.overrideWith((ref) => api),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => socket.dispose());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const SessionDetailScreen(sessionName: 'alpha'),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await _expectBrandPrimitivePresent(tester);
    });

    testWidgets('DashboardScreen renders a brand primitive', (tester) async {
      // `BU.13.D` task 3: the screen was rebuilt onto `briefingBoardProvider`
      // (reused, not a new fetch) rather than `reposProvider` — it now
      // needs `bastionApiProvider` set, same as `RepoDetailScreen` below.
      // Uses the route-aware `FakeHttpTransport` (not this file's local
      // `_FakeHttpTransport`, which always answers `204`/empty and cannot
      // produce a decodable `BoardDto`) so `GET /api/board` resolves to a
      // real tiered board and the screen renders past its loading/error
      // states into the `Eyebrow`/`SeverityRow` tree the sweep checks for.
      final boardTransport = FakeHttpTransport();
      boardTransport.on(
        'GET',
        '/api/board',
        status: 200,
        body: {
          'scope': 'hq',
          'lanes': <String, dynamic>{},
          'repos': [
            {
              'repo': 'alpha',
              'lanes': {
                'now': [
                  {'id': 'A.1', 'title': 'Ship it', 'repo': 'alpha'},
                ],
              },
            },
          ],
          'stale': false,
        },
      );
      final api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: boardTransport,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bastionApiProvider.overrideWith((ref) => api)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _expectBrandPrimitivePresent(tester);
    });

    testWidgets('RepoDetailScreen renders a brand primitive', (tester) async {
      const status = RepoStatusDto(
        name: 'alpha',
        now: 'shipping task 5',
        next: 'wire dashboard',
        blocked: '',
        hasHandoff: false,
        momentumNow: 'momentum now',
        momentumNext: 'momentum next',
        momentumBlocked: '',
        momentumImprove: 'momentum improve',
        momentumRecurring: 'momentum recurring',
      );
      final api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: _FakeHttpTransport(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // `BU.13.C` task 3 wires RepoDetailScreen's stat row to
            // `repoBoardProvider`, which reads `bastionApiProvider` — must
            // be set for the screen to build at all now, same as the other
            // screens in this sweep.
            bastionApiProvider.overrideWith((ref) => api),
            repoWorkflowsProvider('alpha').overrideWith(
              (ref) => _FakeRepoWorkflowsNotifier(
                const RepoWorkflowsState(
                  status: status,
                  workflows: [],
                  loading: false,
                ),
                repoName: 'alpha',
              ),
            ),
            repoHandoffProvider(
              'alpha',
            ).overrideWith((ref) => Future.value(null)),
          ],
          child: const MaterialApp(home: RepoDetailScreen(repoName: 'alpha')),
        ),
      );
      await tester.pump();

      await _expectBrandPrimitivePresent(tester);
    });

    testWidgets('QuickActionsScreen renders a brand primitive', (tester) async {
      final api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: _FakeHttpTransport(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bastionApiProvider.overrideWith((ref) => api),
            sessionsProvider.overrideWith(
              (ref) => _FakeSessionsNotifier(const []),
            ),
            secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
          ],
          child: const MaterialApp(home: QuickActionsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _expectBrandPrimitivePresent(tester);
    });

    testWidgets('SettingsScreen renders a brand primitive', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _expectBrandPrimitivePresent(tester);
    });
  });
}
