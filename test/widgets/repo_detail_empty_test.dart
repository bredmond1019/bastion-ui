// Empty-state + demoted-prose + no-comma-run tests for `RepoDetailScreen`
// (`BU.13.C` task 5).
//
// Mirrors `repo_detail_rows_test.dart`'s approach: `RepoDetailBlockLanes`
// takes an already-resolved `BriefingSectionState<BoardLaneDto>`, so these
// tests construct fixtures directly against the pure model layer rather
// than wiring Riverpod/HTTP.

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/screens/repo_detail_screen.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;
import 'package:bastion_ui/state/workflows_provider.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_http_transport.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Every lane empty — the pathological case the whole task guards.
const _allEmptyLane = BoardLaneDto();

const _readyNowBlock = BoardBlockDto(
  id: 'BU.1.A',
  title: '1:1 chat',
  repo: 'bastion-ui',
  wave: 1,
  ready: true,
  dependentCount: 2,
);

const _notReadyNextBlock = BoardBlockDto(
  id: 'BU.2.A',
  title: 'Push notifications',
  repo: 'bastion-ui',
  wave: 2,
  ready: false,
);

const _blockedBlock = BoardBlockDto(
  id: 'BU.3.A',
  title: 'Reputation layer',
  repo: 'bastion-ui',
  wave: 2,
  ready: false,
  unmetCount: 1,
  blockedBy: [BlockDepDto(repo: 'bastion-ui', id: 'BU.1.A')],
);

/// `now`/`next`/`blocked` populated; `deferred`/`finished` left empty — the
/// mixed case, so populated lanes and empty lanes must coexist correctly.
const _mixedLane = BoardLaneDto(
  now: [_readyNowBlock],
  next: [_notReadyNextBlock],
  blocked: [_blockedBlock],
);

/// Minimal fake for `repoWorkflowsProvider`'s family notifier — this file's
/// full-screen test only needs a resolved [RepoStatusDto], not real
/// workflow/socket wiring, mirroring `repo_detail_test.dart`'s fake.
class _FakeRepoWorkflowsNotifier extends StateNotifier<RepoWorkflowsState>
    implements RepoWorkflowsNotifier {
  _FakeRepoWorkflowsNotifier(super.state, {required this.repoName});

  @override
  final String repoName;
}

Future<void> _pumpLanes(
  WidgetTester tester,
  BriefingSectionState<BoardLaneDto> boardState,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepoDetailBlockLanes(boardState: boardState),
        ),
      ),
    ),
  );
}

/// Collects every rendered `Text` widget's flattened string data — used to
/// scan for a literal `[]` or a comma-joined run of block records, neither
/// of which should ever reach the screen.
List<String> _renderedTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RepoDetailBlockLanes empty states', () {
    testWidgets('each lane renders its own empty-state wording', (
      tester,
    ) async {
      await _pumpLanes(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_allEmptyLane),
      );

      expect(find.text('Nothing in progress right now.'), findsOneWidget);
      expect(find.text('Nothing queued next.'), findsOneWidget);
      expect(find.text('Nothing blocked.'), findsOneWidget);
      expect(find.text('Nothing deferred.'), findsOneWidget);
      expect(find.text('Nothing finished yet.'), findsOneWidget);

      // Every lane's empty-state text carries its own key, distinguishing
      // it from its siblings.
      for (final laneId in ['now', 'next', 'blocked', 'deferred', 'finished']) {
        expect(
          find.byKey(ValueKey('repo-detail-lane-empty-$laneId')),
          findsOneWidget,
        );
      }
    });

    testWidgets('no rendered text anywhere equals or contains a literal []', (
      tester,
    ) async {
      await _pumpLanes(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_allEmptyLane),
      );

      for (final text in _renderedTexts(tester)) {
        expect(text, isNot(equals('[]')));
        expect(text, isNot(contains('[]')));
      }
    });

    testWidgets('populated lanes and empty lanes coexist: rows for the former, '
        'wording for the latter', (tester) async {
      await _pumpLanes(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_mixedLane),
      );

      expect(find.byType(SeverityRow), findsNWidgets(3));
      expect(find.text('Nothing deferred.'), findsOneWidget);
      expect(find.text('Nothing finished yet.'), findsOneWidget);
      // Populated lanes must not also render their empty-state wording.
      expect(find.text('Nothing in progress right now.'), findsNothing);
      expect(find.text('Nothing queued next.'), findsNothing);
      expect(find.text('Nothing blocked.'), findsNothing);
    });

    testWidgets('no rendered text contains a comma-joined run of block ids', (
      tester,
    ) async {
      await _pumpLanes(
        tester,
        const BriefingSectionLoaded<BoardLaneDto>(_mixedLane),
      );

      // The regression this whole block exists to fix: a single Text node
      // stringing multiple block records together as a comma-separated
      // run, e.g. "1:1 chat, Push notifications, Reputation layer" or
      // "BU.1.A, BU.2.A, BU.3.A". A row's own meta line legitimately packs
      // several facts about *one* block (its own id plus, in the blocked
      // lane, the id it waits on) separated by ` · ` — that is not the
      // regression. What must never appear is two-or-more distinct block
      // ids joined by a bare comma.
      final commaJoinedIds = RegExp(r'BU\.\d+\.[A-Z](?:,\s*BU\.\d+\.[A-Z])+');
      // The three fixture block titles, comma-joined — the exact shape a
      // reintroduced `.join(', ')` over the block list would produce.
      const joinedTitles = '1:1 chat, Push notifications, Reputation layer';
      for (final text in _renderedTexts(tester)) {
        expect(
          commaJoinedIds.hasMatch(text),
          isFalse,
          reason: 'found a comma-joined run of block ids in: "$text"',
        );
        expect(
          text,
          isNot(contains(joinedTitles)),
          reason: 'found a comma-joined run of block titles in: "$text"',
        );
      }
    });
  });

  group('RepoDetailScreen — demoted momentum prose', () {
    testWidgets(
      'the momentum prose still renders, after the structured rows in '
      'widget order',
      (tester) async {
        // The now/next/blocked lanes lengthen the screen's `ListView`
        // enough that the default 800x600 test viewport's `SliverList`
        // does not materialize the status table below them in one pump —
        // the same task-boundary issue task 4 hit for the workflow-progress
        // rows (see this spec's Amendment Log). Widen the viewport rather
        // than asserting on a screen the operator would never actually see
        // this cropped.
        final originalSize = tester.view.physicalSize;
        final originalRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalRatio;
        });

        const repoName = 'alpha';

        final transport = FakeHttpTransport()
          ..on(
            'GET',
            '/api/board',
            status: 200,
            body: {
              'scope': 'project',
              'lanes': <String, dynamic>{},
              'repos': [
                {
                  'repo': repoName,
                  'tier': 'core',
                  'lanes': {
                    'now': [
                      {
                        'id': 'BU.1.A',
                        'title': '1:1 chat',
                        'repo': repoName,
                        'wave': 1,
                        'ready': true,
                        'dependent_count': 2,
                      },
                    ],
                    'next': [
                      {
                        'id': 'BU.2.A',
                        'title': 'Push notifications',
                        'repo': repoName,
                        'wave': 2,
                        'ready': false,
                      },
                    ],
                    'blocked': [
                      {
                        'id': 'BU.3.A',
                        'title': 'Reputation layer',
                        'repo': repoName,
                        'wave': 2,
                        'ready': false,
                        'unmet_count': 1,
                        'blocked_by': [
                          {'type': 'block', 'repo': repoName, 'id': 'BU.1.A'},
                        ],
                      },
                    ],
                    'deferred': <dynamic>[],
                    'finished': <dynamic>[],
                  },
                },
              ],
              'stale': false,
            },
          );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bastionApiProvider.overrideWith(
                (ref) => BastionApi(
                  host: 'test-host',
                  port: 4317,
                  token: 'test-token',
                  transport: transport,
                ),
              ),
              repoWorkflowsProvider(repoName).overrideWith(
                (ref) => _FakeRepoWorkflowsNotifier(
                  RepoWorkflowsState(
                    status: RepoStatusDto(
                      name: repoName,
                      now: 'shipping task 5',
                      next: 'wire dashboard',
                      blocked: '',
                      hasHandoff: false,
                      momentumNow: 'momentum now text',
                      momentumNext: 'momentum next text',
                      momentumBlocked: '',
                      momentumImprove: 'momentum improve text',
                      momentumRecurring: 'momentum recurring text',
                    ),
                    workflows: const [],
                    loading: false,
                  ),
                  repoName: repoName,
                ),
              ),
              repoHandoffProvider(
                repoName,
              ).overrideWith((ref) => Future.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const RepoDetailScreen(repoName: repoName),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // The structured block lanes and the momentum prose both render...
        expect(find.byType(SeverityRow), findsNWidgets(3));
        expect(find.text('momentum now text'), findsOneWidget);

        // ...and the prose comes after the structured rows in widget
        // (paint/traversal) order — never competing with them for the
        // operator's first read.
        final lanesRect = tester.getRect(
          find.byKey(const ValueKey('repo-detail-block-lanes')),
        );
        final statusTableRect = tester.getRect(
          find.byKey(const ValueKey('repo-status-table')),
        );
        expect(statusTableRect.top, greaterThan(lanesRect.top));
      },
    );
  });

  group('RepoDetailBlockLanes loading/error', () {
    testWidgets('renders nothing (not an empty state) while loading', (
      tester,
    ) async {
      await _pumpLanes(tester, const BriefingSectionLoading<BoardLaneDto>());

      expect(find.text('Nothing in progress right now.'), findsNothing);
      expect(
        find.byKey(const ValueKey('repo-detail-block-lanes')),
        findsNothing,
      );
    });

    testWidgets('renders nothing (not an empty state) on error', (
      tester,
    ) async {
      await _pumpLanes(
        tester,
        const BriefingSectionError<BoardLaneDto>('Server error (500)'),
      );

      expect(find.text('Nothing blocked.'), findsNothing);
      expect(
        find.byKey(const ValueKey('repo-detail-block-lanes')),
        findsNothing,
      );
    });
  });
}
