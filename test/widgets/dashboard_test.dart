// Widget tests for DashboardScreen (`BU.13.D` task 3).
//
// The screen was rebuilt onto `lib/state/portfolio_ranking.dart` (task 2):
// it now reads `briefingBoardProvider` (`briefing_provider.dart`, reused
// rather than rebuilt — see `dashboard_screen.dart`'s doc comment) and
// renders repos as tiered `SeverityRow`s with a `LaneBar` trailing detail,
// in place of the old flat `reposProvider`/`repoWorkflowsProvider` list
// with a one-word `StatusPill`.
//
// `briefingBoardProvider` is driven through a real `BastionApi` backed by
// `FakeHttpTransport` (mirrors `test/screens/briefing_reachable_test.dart`
// and `test/main_wiring_test.dart`'s pattern for provider-owning screens)
// rather than a hand-rolled fake `StateNotifier` — `BriefingSectionNotifier`
// is concrete, not an interface, so overriding the provider directly would
// mean subclassing it just to seed a state, and this repo already has an
// established fixture for driving it end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _blockJson(String id, String repo) => {
  'id': id,
  'title': 'Block $id',
  'repo': repo,
};

/// A board response with two repos: `alpha` (needs-attention — a blocked
/// block with an operator gate), `beta` (active — one `now` block).
/// `gamma` (quiet — no blocks at all) rounds out the fixture so all three
/// tiers render.
final Map<String, dynamic> _threeRepoBoardJson = {
  'scope': 'hq',
  'lanes': const {},
  'repos': [
    {
      'repo': 'alpha',
      'lanes': {
        'blocked': [
          {
            ..._blockJson('A.1', 'alpha'),
            'blocked_by': [
              {
                'type': 'operator',
                'slug': 'op-slug',
                'exit': 'sign-off',
                'start': '2026-08-01',
              },
            ],
          },
        ],
        'finished': [_blockJson('A.2', 'alpha'), _blockJson('A.3', 'alpha')],
      },
    },
    {
      'repo': 'beta',
      'lanes': {
        'now': [_blockJson('B.1', 'beta')],
      },
    },
    {'repo': 'gamma', 'lanes': const {}},
  ],
  'stale': false,
};

FakeHttpTransport _transportWithBoard(Object boardBody) {
  final t = FakeHttpTransport();
  t.on('GET', '/api/board', status: 200, body: boardBody);
  return t;
}

Widget _buildScreen(
  FakeHttpTransport transport, {
  RouteFactory? onGenerateRoute,
}) {
  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: transport,
  );
  return ProviderScope(
    overrides: [bastionApiProvider.overrideWith((ref) => api)],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const DashboardScreen(),
      onGenerateRoute: onGenerateRoute,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen', () {
    testWidgets('renders a tier heading with a count per tier, and one row '
        'per repo', (tester) async {
      await tester.pumpWidget(
        _buildScreen(_transportWithBoard(_threeRepoBoardJson)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('NEEDS ATTENTION · 1'), findsOneWidget);
      expect(find.text('ACTIVE · 1'), findsOneWidget);
      expect(find.text('QUIET · 1'), findsOneWidget);

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      // The quiet tier collapses to a summary row by default (task 5) —
      // with a single quiet repo the summary text is just its name, so
      // `gamma` is still findable without expanding.
      expect(find.text('gamma'), findsOneWidget);

      // gamma's row is collapsed, so only alpha's and beta's LaneBar/
      // StatusPill render until the quiet tier is expanded.
      expect(find.byType(LaneBar), findsNWidgets(2));
      expect(find.byType(StatusPill), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
      );
      await tester.pumpAndSettle();

      // One LaneBar trailing detail per row.
      expect(find.byType(LaneBar), findsNWidgets(3));
      // One StatusPill (inside each SeverityRow) per row.
      expect(find.byType(StatusPill), findsNWidgets(3));
    });

    testWidgets(
      "a needs-attention repo's LaneBar segments sum to its block total "
      '(minus deferred)',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen(_transportWithBoard(_threeRepoBoardJson)),
        );
        await tester.pump();
        await tester.pump();

        final alphaCard = find.ancestor(
          of: find.text('alpha'),
          matching: find.byType(SeverityRow),
        );
        final laneBar = tester.widget<LaneBar>(
          find.descendant(of: alphaCard, matching: find.byType(LaneBar)),
        );

        // alpha: 1 blocked, 2 finished (done), 0 now, 0 next.
        expect(laneBar.done, 2);
        expect(laneBar.now, 0);
        expect(laneBar.blocked, 1);
        expect(laneBar.next, 0);
        expect(laneBar.done + laneBar.now + laneBar.blocked + laneBar.next, 3);
      },
    );

    testWidgets('an active repo shows a RUNNING pill, a quiet repo shows '
        'ON TRACK', (tester) async {
      await tester.pumpWidget(
        _buildScreen(_transportWithBoard(_threeRepoBoardJson)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('RUNNING'), findsOneWidget);

      // gamma's ON TRACK pill is inside the quiet tier's row, which is
      // collapsed to a summary row by default (task 5) — expand it first.
      await tester.tap(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
      );
      await tester.pumpAndSettle();

      expect(find.text('ON TRACK'), findsOneWidget);
    });

    testWidgets('shows empty state when there are no repos', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          _transportWithBoard(const {
            'scope': 'hq',
            'lanes': <String, dynamic>{},
            'repos': <dynamic>[],
            'stale': false,
          }),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(StatusPill), findsNothing);
      expect(find.text('No repos registered'), findsOneWidget);
    });

    testWidgets('tapping a row navigates toward the repo detail route', (
      tester,
    ) async {
      String? pushedRoute;
      await tester.pumpWidget(
        _buildScreen(
          _transportWithBoard(_threeRepoBoardJson),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('detail')),
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();

      expect(pushedRoute, repoDetailRouteName('beta'));
    });

    testWidgets('shows an inline error with retry on a board fetch failure', (
      tester,
    ) async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/board', status: 500, body: {'code': 'E001'});
      await tester.pumpWidget(_buildScreen(t));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('dashboard-retry')), findsOneWidget);
      expect(find.text('No repos registered'), findsNothing);
    });
  });
}
