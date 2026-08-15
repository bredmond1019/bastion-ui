// Widget tests for RunsScreen (`BU.13.E` task 5).
//
// Covers the four acceptance criteria this task owns: runs render, a tap
// drills into a VERTICAL node list, a suspended run reads distinctly from
// a finished one, and an empty `GET /api/runs` renders the explanatory
// empty state rather than an error or an endless spinner.
//
// Wires a real `BastionSocket`/`BastionApi` pair against fake transports
// (mirrors `test/state/runs_provider_test.dart`'s fixtures exactly) rather
// than overriding `runsProvider` directly, since `runsProvider` is typed
// `StateNotifierProvider<RunsNotifier, ...>` and `RunsNotifier` itself owns
// the subscribe/unsubscribe lifecycle this block cares about.

// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';

import 'package:bastion_ui/screens/runs_screen.dart';
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
// Fakes (mirrors runs_provider_test.dart / runs_reachable_test.dart)
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

  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }
}

Future<void> pump(WidgetTester tester, [int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<Widget> buildHarness({required FakeHttpTransport httpTransport}) async {
  final wsTransport = _FakeWsTransport();
  final socket = BastionSocket(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transportFactory: (uri, {headers}) => wsTransport,
  );
  socket.connect();
  wsTransport.completeReady();

  final api = BastionApi(
    host: 'test-host',
    port: 4317,
    token: 'test-token',
    transport: httpTransport,
  );

  return ProviderScope(
    overrides: [
      bastionSocketProvider.overrideWith((ref) => socket),
      bastionApiProvider.overrideWith((ref) => api),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const RunsScreen()),
  );
}

void main() {
  group('RunsScreen', () {
    testWidgets('renders a run row for each live run', (tester) async {
      final http = FakeHttpTransport();
      http.on(
        'GET',
        '/api/runs',
        status: 200,
        body: [
          {
            'run_id': 'run-alpha',
            'status': 'running',
            'spec_slug': '13.E-live-runs',
            'updated_at': '2026-08-15T12:00:00Z',
          },
        ],
      );

      await tester.pumpWidget(await buildHarness(httpTransport: http));
      await pump(tester);

      expect(find.text('run-alpha'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('status-badge-running')),
        findsOneWidget,
      );
    });

    testWidgets(
      'no engine mounted (200 []) renders the explanatory empty state, '
      'never an error or a spinner',
      (tester) async {
        final http = FakeHttpTransport();
        http.on(
          'GET',
          '/api/runs',
          status: 200,
          body: <Map<String, dynamic>>[],
        );

        await tester.pumpWidget(await buildHarness(httpTransport: http));
        await pump(tester);

        expect(find.byKey(const ValueKey('runs-empty-state')), findsOneWidget);
        expect(find.text('No live runs'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'a suspended run reads distinctly from a finished run — different '
      'tone AND different icon, not colour alone',
      (tester) async {
        final http = FakeHttpTransport();
        http.on(
          'GET',
          '/api/runs',
          status: 200,
          body: [
            {
              'run_id': 'run-suspended',
              'status': 'suspended',
              'updated_at': '2026-08-15T12:00:00Z',
            },
            {
              'run_id': 'run-done',
              'status': 'success',
              'updated_at': '2026-08-15T12:00:00Z',
            },
          ],
        );

        await tester.pumpWidget(await buildHarness(httpTransport: http));
        await pump(tester);

        final suspendedBadge = find.byKey(
          const ValueKey('status-badge-suspended'),
        );
        final doneBadge = find.byKey(const ValueKey('status-badge-success'));
        expect(suspendedBadge, findsOneWidget);
        expect(doneBadge, findsOneWidget);

        // Different icon (non-colour channel): suspended reads paused,
        // finished reads done.
        expect(
          find.descendant(
            of: suspendedBadge,
            matching: find.byIcon(Icons.pause_circle_filled),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: doneBadge,
            matching: find.byIcon(Icons.check_circle),
          ),
          findsOneWidget,
        );

        // Different tone: suspended stays live (active tone), finished
        // settles (success tone) — asserted via the two icons resolving
        // to different colours, since both draw from the same
        // `StatusTones` accessor.
        final suspendedIcon = tester.widget<Icon>(
          find.descendant(
            of: suspendedBadge,
            matching: find.byIcon(Icons.pause_circle_filled),
          ),
        );
        final doneIcon = tester.widget<Icon>(
          find.descendant(
            of: doneBadge,
            matching: find.byIcon(Icons.check_circle),
          ),
        );
        expect(suspendedIcon.color, isNot(equals(doneIcon.color)));
      },
    );

    testWidgets(
      'tapping a run drills into its node list, rendered VERTICALLY',
      (tester) async {
        final http = FakeHttpTransport();
        http.on(
          'GET',
          '/api/runs',
          status: 200,
          body: [
            {
              'run_id': 'run-alpha',
              'status': 'running',
              'updated_at': '2026-08-15T12:00:00Z',
            },
          ],
        );
        http.on(
          'GET',
          '/api/runs/run-alpha',
          status: 200,
          body: {
            'run_id': 'run-alpha',
            'nodes': [
              {
                'node': 'FirstNode',
                'status': 'success',
                'started_at': '2026-08-15T11:00:00Z',
                'completed_at': '2026-08-15T11:05:00Z',
              },
              {'node': 'SecondNode', 'status': 'running'},
            ],
          },
        );

        await tester.pumpWidget(await buildHarness(httpTransport: http));
        await pump(tester);

        await tester.tap(find.byKey(const ValueKey('run-row-tap')));
        await pump(tester);

        final list = find.byKey(const ValueKey('run-node-list'));
        expect(list, findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);

        final firstRow = find.byKey(const ValueKey('node-row-FirstNode'));
        final secondRow = find.byKey(const ValueKey('node-row-SecondNode'));
        expect(firstRow, findsOneWidget);
        expect(secondRow, findsOneWidget);

        // Vertical list, not a graph: SecondNode's row sits strictly below
        // FirstNode's row on the same column.
        final firstCenter = tester.getCenter(firstRow);
        final secondCenter = tester.getCenter(secondRow);
        expect(secondCenter.dy, greaterThan(firstCenter.dy));

        // Back affordance returns to the list.
        await tester.tap(find.byKey(const ValueKey('runs-detail-back')));
        await pump(tester);
        expect(find.byKey(const ValueKey('run-row-tap')), findsOneWidget);
      },
    );
  });
}
