// Widget tests for the Dashboard's quiet-tier collapse and the
// `StatusPill` tone fix (`BU.13.D` task 5, D4 constraint 3).
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
import 'package:bastion_ui/theme/status_tones.dart';
import 'package:bastion_ui/theme/tokens.dart';
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

/// Five quiet repos (no blocks at all, so no `now`/`blocked` lane and no
/// `last_touched` to promote any of them into needs-attention) named so
/// their tie-broken-by-name-ascending order within the quiet tier is
/// predictable: alpha, bravo, charlie, delta, echo.
final Map<String, dynamic> _fiveQuietReposBoardJson = {
  'scope': 'hq',
  'lanes': const {},
  'repos': [
    for (final name in ['alpha', 'bravo', 'charlie', 'delta', 'echo'])
      {'repo': name, 'lanes': const {}},
  ],
  'stale': false,
};

/// One active repo (`now` block -> `PortfolioTier.active`) and one quiet
/// repo (`PortfolioTier.quiet`), for the tone-loudness assertion.
final Map<String, dynamic> _activeAndIdleBoardJson = {
  'scope': 'hq',
  'lanes': const {},
  'repos': [
    {
      'repo': 'running-repo',
      'lanes': {
        'now': [_blockJson('R.1', 'running-repo')],
      },
    },
    {'repo': 'idle-repo', 'lanes': const {}},
  ],
  'stale': false,
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen quiet-tier collapse', () {
    testWidgets(
      'the quiet tier collapses to one summary row naming repos and a '
      'correct +N count',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen(_transportWithBoard(_fiveQuietReposBoardJson)),
        );
        await tester.pump();
        await tester.pump();

        // The tier heading always renders, collapsed or not.
        expect(find.text('QUIET · 5'), findsOneWidget);

        // Collapsed by default: one summary row, no per-repo rows.
        expect(
          find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
          findsOneWidget,
        );
        expect(find.text('alpha · bravo · charlie  +2'), findsOneWidget);
        for (final name in ['alpha', 'bravo', 'charlie', 'delta', 'echo']) {
          expect(
            find.byKey(ValueKey('portfolio-row-$name')),
            findsNothing,
            reason: '$name should not render its own row while collapsed',
          );
        }
        expect(find.byType(SeverityRow), findsNothing);
      },
    );

    testWidgets('expanding the quiet tier shows every repo, and collapsing '
        'restores the summary', (tester) async {
      // Five expanded rows plus the collapse footer don't materialize
      // under the default 800x600 test viewport (the `SliverList`
      // materialization failure mode `BU.13.C` hit) — a taller viewport,
      // restored in teardown, never a shortened screen.
      final originalSize = tester.view.physicalSize;
      final originalRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalRatio;
      });

      await tester.pumpWidget(
        _buildScreen(_transportWithBoard(_fiveQuietReposBoardJson)),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
      );
      await tester.pumpAndSettle();

      // Expanded: every quiet repo has its own row; the tier heading is
      // unchanged; the summary row is gone.
      expect(find.text('QUIET · 5'), findsOneWidget);
      for (final name in ['alpha', 'bravo', 'charlie', 'delta', 'echo']) {
        expect(find.byKey(ValueKey('portfolio-row-$name')), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
        findsNothing,
      );
      expect(find.byType(SeverityRow), findsNWidgets(5));

      await tester.tap(find.byKey(const ValueKey('portfolio-quiet-collapse')));
      await tester.pumpAndSettle();

      // Collapsed again: the summary row is back, no per-repo rows.
      expect(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
        findsOneWidget,
      );
      expect(find.byType(SeverityRow), findsNothing);
      expect(find.text('QUIET · 5'), findsOneWidget);
    });
  });

  group('DashboardScreen StatusPill tone fix (D4 constraint 3)', () {
    testWidgets("an active repo's pill tone reads louder than an idle repo's", (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(_transportWithBoard(_activeAndIdleBoardJson)),
      );
      await tester.pump();
      await tester.pump();

      // Expand the (single-repo) quiet tier to reach idle-repo's pill.
      await tester.tap(
        find.byKey(const ValueKey('portfolio-quiet-summary-tap')),
      );
      await tester.pumpAndSettle();

      final runningPill = tester.widget<StatusPill>(
        find.descendant(
          of: find.byKey(const ValueKey('portfolio-row-running-repo')),
          matching: find.byType(StatusPill),
        ),
      );
      final idlePill = tester.widget<StatusPill>(
        find.descendant(
          of: find.byKey(const ValueKey('portfolio-row-idle-repo')),
          matching: find.byType(StatusPill),
        ),
      );

      expect(runningPill.label, 'RUNNING');
      expect(idlePill.label, 'ON TRACK');

      // Assert the *tone mapping*, not a hex literal: the active repo's
      // pill must resolve to the loud `tones.active` tone (the same
      // tone this screen's own interactive affordance uses, D4
      // constraint 3's "active must read louder than idle"), and the
      // idle repo's pill must resolve to the muted `tones.neutral`
      // tone — the reverse of the pre-fix mapping.
      final context = tester.element(find.byType(DashboardScreen));
      final tones = Theme.of(context).statusTones;

      expect(
        statusToneFor(runningPill.tone, tones).foreground,
        tones.active.foreground,
      );
      expect(
        statusToneFor(idlePill.tone, tones).foreground,
        tones.neutral.foreground,
      );
      expect(
        statusToneFor(runningPill.tone, tones).foreground,
        isNot(statusToneFor(idlePill.tone, tones).foreground),
      );
    });

    testWidgets(
      'interactive (accent2) and active stay separable without colour',
      (tester) async {
        await tester.pumpWidget(
          _buildScreen(_transportWithBoard(_activeAndIdleBoardJson)),
        );
        await tester.pump();
        await tester.pump();

        final context = tester.element(find.byType(DashboardScreen));
        final tones = Theme.of(context).statusTones;

        // The active pill intentionally shares `accent2`/`tones.active`'s
        // hue with this screen's interactive affordance (the retry
        // `TextButton`, styled with `AppTokens.accent2` —
        // `_retryButtonStyle` in `dashboard_screen.dart`) — so the two must
        // stay separable some other way: shape. The pill is a bordered,
        // filled, dot-leading `Container`; the interactive affordance is a
        // bare `TextButton` with no such decoration.
        expect(
          statusToneFor(StatusPillTone.onTrack, tones).foreground,
          AppTokens.accent2,
          reason:
              'the active pill and the interactive affordance intentionally '
              'share accent2 as their hue',
        );

        final runningPill = find.descendant(
          of: find.byKey(const ValueKey('portfolio-row-running-repo')),
          matching: find.byType(StatusPill),
        );
        expect(runningPill, findsOneWidget);

        final pillContainer = tester.widget<Container>(
          find
              .descendant(of: runningPill, matching: find.byType(Container))
              .first,
        );
        final pillDecoration = pillContainer.decoration as BoxDecoration;
        // The pill's non-hue signal: a hairline border plus a tinted
        // fill and a leading dot — none of which a bare `TextButton`
        // (this screen's only other `accent2` consumer) ever carries.
        expect(pillDecoration.border, isNotNull);
        expect(pillDecoration.color, isNotNull);
        expect(find.byType(TextButton), findsNothing);
      },
    );
  });
}
