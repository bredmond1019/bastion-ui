// Widget tests for the Dashboard's staleness `AgeChip` and activity
// `Sparkline` (`BU.13.D` task 4).
//
// Drives `DashboardScreen` through `briefingBoardProvider` (a real
// `BastionApi` backed by `FakeHttpTransport`), matching
// `test/widgets/dashboard_test.dart`'s established pattern for
// provider-owning screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fixtures — a fixed `now` (task 2/4's determinism contract): the screen
// captures `now` once in `initState`, so all timestamps below are anchored
// relative to real wall-clock `DateTime.now()` at test run time, using
// deltas well inside a single day/hour so no boundary flake is possible.
// ---------------------------------------------------------------------------

Map<String, dynamic> _blockJson(
  String id,
  String repo, {
  DateTime? lastTouched,
}) => {
  'id': id,
  'title': 'Block $id',
  'repo': repo,
  if (lastTouched != null) 'last_touched': lastTouched.toIso8601String(),
};

FakeHttpTransport _transportWithBoard(Object boardBody) {
  final t = FakeHttpTransport();
  t.on('GET', '/api/board', status: 200, body: boardBody);
  return t;
}

Widget _buildScreen(FakeHttpTransport transport) {
  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: transport,
  );
  return ProviderScope(
    overrides: [bastionApiProvider.overrideWith((ref) => api)],
    child: MaterialApp(theme: AppTheme.dark, home: const DashboardScreen()),
  );
}

void main() {
  group('DashboardScreen staleness + activity', () {
    testWidgets(
      'a repo touched moments ago shows a calm AgeChip, a repo touched '
      'well past the staleness threshold shows a warning-toned one',
      (tester) async {
        final now = DateTime.now();
        final board = {
          'scope': 'hq',
          'lanes': const {},
          'repos': [
            {
              'repo': 'fresh-repo',
              'lanes': {
                'now': [
                  _blockJson(
                    'F.1',
                    'fresh-repo',
                    lastTouched: now.subtract(const Duration(minutes: 2)),
                  ),
                ],
              },
            },
            {
              'repo': 'stale-repo',
              'lanes': {
                'finished': [
                  _blockJson(
                    'S.1',
                    'stale-repo',
                    lastTouched: now.subtract(const Duration(days: 9)),
                  ),
                ],
              },
            },
          ],
          'stale': false,
        };

        await tester.pumpWidget(_buildScreen(_transportWithBoard(board)));
        await tester.pump();
        await tester.pump();

        final freshChip = tester.widget<AgeChip>(
          find.descendant(
            of: find.byKey(const ValueKey('portfolio-recency-fresh-repo')),
            matching: find.byType(AgeChip),
          ),
        );
        final staleChip = tester.widget<AgeChip>(
          find.descendant(
            of: find.byKey(const ValueKey('portfolio-recency-stale-repo')),
            matching: find.byType(AgeChip),
          ),
        );

        expect(freshChip.isStale, isFalse);
        expect(staleChip.isStale, isTrue);
      },
    );

    testWidgets('a repo with no last_touched anywhere shows the not-started '
        'treatment, never an AgeChip or a fabricated age', (tester) async {
      final board = {
        'scope': 'hq',
        'lanes': const {},
        'repos': [
          {'repo': 'never-worked-repo', 'lanes': const {}},
        ],
        'stale': false,
      };

      await tester.pumpWidget(_buildScreen(_transportWithBoard(board)));
      await tester.pump();
      await tester.pump();

      final recencySlot = find.byKey(
        const ValueKey('portfolio-recency-never-worked-repo'),
      );
      expect(
        find.descendant(of: recencySlot, matching: find.byType(AgeChip)),
        findsNothing,
      );
      expect(
        find.descendant(of: recencySlot, matching: find.text('not started')),
        findsOneWidget,
      );
      // No age-shaped label ("Nd"/"Nh"/"Nm") and no em dash standing in
      // for one — the exact bug class task 1/2 exist to prevent.
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets(
      'a repo touched inside the last 7 days renders a Sparkline; a repo '
      'with no activity in that window renders none',
      (tester) async {
        final now = DateTime.now();
        final board = {
          'scope': 'hq',
          'lanes': const {},
          'repos': [
            {
              'repo': 'active-history-repo',
              'lanes': {
                'now': [
                  _blockJson(
                    'H.1',
                    'active-history-repo',
                    lastTouched: now.subtract(const Duration(hours: 3)),
                  ),
                ],
                'finished': [
                  _blockJson(
                    'H.2',
                    'active-history-repo',
                    lastTouched: now.subtract(const Duration(days: 2)),
                  ),
                ],
              },
            },
            {
              'repo': 'no-activity-repo',
              'lanes': {
                'finished': [
                  _blockJson(
                    'N.1',
                    'no-activity-repo',
                    lastTouched: now.subtract(const Duration(days: 40)),
                  ),
                ],
              },
            },
          ],
          'stale': false,
        };

        await tester.pumpWidget(_buildScreen(_transportWithBoard(board)));
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('portfolio-sparkline-active-history-repo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('portfolio-sparkline-no-activity-repo')),
          findsNothing,
        );
      },
    );
  });
}
