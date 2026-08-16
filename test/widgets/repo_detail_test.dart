// Widget tests for RepoDetailScreen.
//
// Overrides `repoWorkflowsProvider` (a fake StateNotifier, mirroring
// `dashboard_test.dart`'s override style) and `repoHandoffProvider` directly
// with a resolved Future — no real socket/API involved.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;
import 'package:bastion_ui/state/workflows_provider.dart';
import 'package:bastion_ui/widgets/workflow_progress.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Builds the shared [FakeHttpTransport] for `bastionApiProvider` — this
/// file's tests exercise the status/handoff/workflow fields, not
/// `repoBoardProvider` (`BU.13.C` task 1), but the screen now watches it as
/// of task 3's stat row, so `bastionApiProvider` must resolve to *something*
/// for the screen to build at all. `RepoDetailScreen`/`repoBoardProvider`
/// only ever call `GET /api/board`; a 204/empty response there resolves
/// `repoBoardProvider` to its error state, which none of these tests assert
/// on — matching the pre-migration always-204 fake's effective behavior.
FakeHttpTransport _buildTransport() =>
    FakeHttpTransport()..on('GET', '/api/board', status: 204, body: '');

class _FakeRepoWorkflowsNotifier extends StateNotifier<RepoWorkflowsState>
    implements RepoWorkflowsNotifier {
  _FakeRepoWorkflowsNotifier(super.state, {required this.repoName});

  @override
  final String repoName;
}

RepoStatusDto _status({bool hasHandoff = false}) => RepoStatusDto(
  name: 'alpha',
  now: 'shipping task 5',
  next: 'wire dashboard',
  blocked: '',
  hasHandoff: hasHandoff,
  momentumNow: 'momentum now',
  momentumNext: 'momentum next',
  momentumBlocked: '',
  momentumImprove: 'momentum improve',
  momentumRecurring: 'momentum recurring',
);

WorkflowStateDto _workflow({String status = 'running'}) => WorkflowStateDto(
  specSlug: '2.A-dashboard-repo-detail',
  branch: '2.A-dashboard-repo-detail-flow',
  status: status,
  currentTask: 5,
  startedAt: '2026-07-02T10:00:00Z',
  updatedAt: '2026-07-02T10:15:00Z',
);

Widget _buildScreen({
  required RepoWorkflowsState workflowsState,
  HandoffInfo? handoff,
  String repoName = 'alpha',
}) {
  return ProviderScope(
    overrides: [
      bastionApiProvider.overrideWith(
        (ref) => BastionApi(
          host: 'test-host',
          port: 4317,
          token: 'test-token',
          transport: _buildTransport(),
        ),
      ),
      repoWorkflowsProvider(repoName).overrideWith(
        (ref) => _FakeRepoWorkflowsNotifier(workflowsState, repoName: repoName),
      ),
      repoHandoffProvider(
        repoName,
      ).overrideWith((ref) => Future.value(handoff)),
    ],
    child: MaterialApp(home: RepoDetailScreen(repoName: repoName)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RepoDetailScreen', () {
    testWidgets('renders the parsed status fields', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          workflowsState: RepoWorkflowsState(
            status: _status(),
            workflows: const [],
            loading: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('shipping task 5'), findsOneWidget);
      expect(find.text('wire dashboard'), findsOneWidget);
      expect(find.text('momentum now'), findsOneWidget);
      expect(find.byKey(const ValueKey('repo-status-table')), findsOneWidget);
    });

    testWidgets('renders handoff markdown body when present', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          workflowsState: RepoWorkflowsState(
            status: _status(hasHandoff: true),
            workflows: const [],
            loading: false,
          ),
          handoff: const HandoffInfo(
            title: 'Handoff — BU.2.A',
            body: '## Summary\nDone with task 5.',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('repo-handoff-section')),
        findsOneWidget,
      );
      expect(find.text('Handoff — BU.2.A'), findsOneWidget);
      expect(find.byKey(const ValueKey('markdown-view-body')), findsOneWidget);
    });

    testWidgets('omits the handoff section when has_handoff is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          workflowsState: RepoWorkflowsState(
            status: _status(hasHandoff: false),
            workflows: const [],
            loading: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('repo-handoff-section')), findsNothing);
      expect(find.byKey(const ValueKey('markdown-view-body')), findsNothing);
    });

    testWidgets('renders a workflow progress row per entry', (tester) async {
      // Task 4 (BU.13.C) added the now/next/blocked stat row + block-lane
      // rows above the status table, lengthening the screen's `ListView`
      // enough that the pre-existing default test viewport (800x600) no
      // longer materializes the workflow-progress rows in the `SliverList`
      // — a task-boundary defect (see the spec's Amendment Log), not a
      // screen defect. Widen the viewport rather than shrinking the screen:
      // the rows still render at real device sizes, this just gives the
      // `SliverList` enough room to lay them all out in one pump.
      final originalSize = tester.view.physicalSize;
      final originalRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalRatio;
      });

      await tester.pumpWidget(
        _buildScreen(
          workflowsState: RepoWorkflowsState(
            status: _status(),
            workflows: [
              _workflow(status: 'running'),
              _workflow(status: 'done'),
            ],
            loading: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(WorkflowProgress), findsNWidgets(2));
      expect(find.textContaining('task 5 — running'), findsOneWidget);
      expect(find.textContaining('task 5 — done'), findsOneWidget);
    });
  });
}
