// Regression test for `BU.ticket.dashboard-now-render`, carried forward
// onto the `BU.13.D` task 3 rebuild.
//
// The original bug: a repo whose `now` line arrived as the empty-collection
// sentinel `"[]"` rendered that literal string instead of nothing. The
// rebuilt Dashboard no longer reads `RepoSummaryDto.now` at all — every
// row's meta line is now built entirely from typed `BoardBlockDto` lane
// counts (`PortfolioRepoEntry.blockTotal` etc., `dashboard_screen.dart`'s
// `_RepoRow._meta`), so there is no raw server string left to leak a
// sentinel through. This test pins that discipline for the new data shape:
// a repo with zero blocks renders "0 blocks", never the literal `"[]"`,
// and a repo with real blocks still renders its real count.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/screens/dashboard_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;
import 'package:bastion_ui/theme/app_theme.dart';

import '../support/fake_http_transport.dart';

Widget _buildScreen(Object boardBody) {
  final t = FakeHttpTransport();
  t.on('GET', '/api/board', status: 200, body: boardBody);
  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: t,
  );
  return ProviderScope(
    overrides: [bastionApiProvider.overrideWith((ref) => api)],
    child: MaterialApp(theme: AppTheme.dark, home: const DashboardScreen()),
  );
}

void main() {
  group('DashboardScreen empty now (BU.ticket.dashboard-now-render, carried '
      'onto BU.13.D task 3)', () {
    testWidgets(
      'a repo with zero blocks renders "0 blocks", never the literal "[]"',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen(const {
            'scope': 'hq',
            'lanes': <String, dynamic>{},
            'repos': [
              {'repo': 'alpha', 'lanes': <String, dynamic>{}},
              {
                'repo': 'beta',
                'lanes': {
                  'now': [
                    {'id': 'B.1', 'title': 'Ship it', 'repo': 'beta'},
                  ],
                },
              },
            ],
            'stale': false,
          }),
        );
        await tester.pump();
        await tester.pump();

        // The regression this ticket exists to prevent: the literal
        // sentinel text must never appear anywhere on screen.
        expect(find.text('[]'), findsNothing);

        // alpha has zero blocks -> quiet tier -> meta reads "0 blocks ...".
        expect(find.textContaining('0 blocks'), findsOneWidget);

        // beta has one real block -> active tier -> meta reflects it.
        expect(find.textContaining('1 blocks · 1 in flight'), findsOneWidget);
      },
    );
  });
}
