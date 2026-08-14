/// Dashboard screen — one row per workspace-registry repo with its
/// current-focus line and a status badge (in-flight workflow / pending
/// handoff / idle).
///
/// Watches `repos_provider.dart`'s [reposProvider] for the repo list; each
/// row additionally watches `workflows_provider.dart`'s
/// [repoWorkflowsProvider] (keyed by repo name) to derive its in-flight
/// state — the same family provider that auto-refetches on a matching
/// `workflow_done` WS event (per `workflows_provider.dart`'s
/// `RepoWorkflowsNotifier`), so a row's in-flight badge clears without a
/// manual refresh once that repo's refetched workflow list reports no
/// `running` entry.
///
/// Re-skinned in `BU.10.C` task 4: the screen wears a display heading with a
/// [HeadingRule] underneath (budget rule: one per screen), and each repo row
/// is now a [PanelCard] wearing a [GradientTopBar] whose hue cycles by list
/// index (`hueForIndex`), an [IconTile] repo glyph, and a [StatusPill] in
/// place of the icon-only [StatusBadge]. The `now`-line empty-state guard
/// (`BU.ticket.dashboard-now-render`) is unchanged: a repo whose `now`
/// normalises to `''` renders no subtitle at all, never the literal `[]`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/repo_status_dto.dart';
import '../state/repos_provider.dart';
import '../state/workflows_provider.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';

/// The WS/REST status string that marks a workflow as currently running
/// (serve-api v0.3 §11.3).
const _runningWorkflowStatus = 'running';

/// Route-name helper for a repo's detail screen (`BU.2.A` Task 5).
///
/// Kept here (rather than importing a not-yet-existing detail screen) so
/// this file can be implemented and tested independently of Task 5 — mirrors
/// `sessions_list_screen.dart`'s `sessionDetailRouteName` pattern. Task 7
/// registers the matching route in `main.dart`.
String repoDetailRouteName(String repoName) => '/repos/$repoName';

/// The three mutually-exclusive dashboard repo-row states — priority order
/// mirrors the pre-brand `StatusBadge`: in-flight outranks pending handoff,
/// which outranks idle.
enum _RepoRowState { idle, inFlight, hasHandoff }

/// Maps a [_RepoRowState] onto the closest-fitting [StatusPillTone]: an
/// in-flight workflow is "in progress", a pending handoff is something the
/// operator needs to act on ("needs you"), and idle means nothing is
/// outstanding ("on track").
StatusPillTone _toneFor(_RepoRowState state) {
  switch (state) {
    case _RepoRowState.inFlight:
      return StatusPillTone.inProgress;
    case _RepoRowState.hasHandoff:
      return StatusPillTone.needsYou;
    case _RepoRowState.idle:
      return StatusPillTone.onTrack;
  }
}

String _labelFor(_RepoRowState state) {
  switch (state) {
    case _RepoRowState.inFlight:
      return 'In flight';
    case _RepoRowState.hasHandoff:
      return 'Handoff';
    case _RepoRowState.idle:
      return 'Idle';
  }
}

/// Live dashboard — one row per workspace-registry repo, sorted by name for
/// a stable display order.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repos = ref.watch(reposProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _DashboardHeading(),
          ),
          Expanded(
            child: repos.isEmpty
                ? Center(
                    child: Text(
                      'No repos registered',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppTokens.inkFaint,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.read(reposProvider.notifier).refresh(),
                    child: _DashboardListView(repos: repos),
                  ),
          ),
        ],
      ),
    );
  }
}

/// This screen's display heading — one [HeadingRule] underneath, per the
/// block's budget rule (one per screen).
class _DashboardHeading extends StatelessWidget {
  const _DashboardHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repositories',
          style: AppTypography.textTheme.headlineSmall?.copyWith(
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        const HeadingRule(),
      ],
    );
  }
}

class _DashboardListView extends StatelessWidget {
  const _DashboardListView({required this.repos});

  final List<RepoSummaryDto> repos;

  @override
  Widget build(BuildContext context) {
    final sorted = [...repos]..sort((a, b) => a.name.compareTo(b.name));

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final repo = sorted[index];
        return _RepoRow(key: ValueKey(repo.name), repo: repo, index: index);
      },
    );
  }
}

/// One dashboard row — watches [repoWorkflowsProvider] keyed by
/// [repo.name] to derive the in-flight badge state, independent of every
/// other row.
class _RepoRow extends ConsumerWidget {
  const _RepoRow({super.key, required this.repo, required this.index});

  final RepoSummaryDto repo;

  /// This row's position in the (sorted) repo list, used to cycle the
  /// [GradientTopBar]'s hue via `hueForIndex` so adjacent cards don't read
  /// identically — the same cadence `session_card.dart` uses.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflows = ref.watch(repoWorkflowsProvider(repo.name));
    final inFlight = workflows.workflows.any(
      (w) => w.status == _runningWorkflowStatus,
    );

    final state = inFlight
        ? _RepoRowState.inFlight
        : (repo.hasHandoff ? _RepoRowState.hasHandoff : _RepoRowState.idle);

    // Built on a plain `Row`, not a `ListTile` — mirrors `session_card.dart`
    // (`BU.10.C` task 2). `ListTile.trailing` asserts when its measured
    // width plus content padding meets the tile's own width (it happens on
    // this exact row once a wide `StatusPill` label like "IN FLIGHT" meets
    // a narrower embedding, e.g. the tablet split-view rail) — a `Row` with
    // an `Expanded` middle column has no such failure mode.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: PanelCard(
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pushNamed(repoDetailRouteName(repo.name)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Budget rule: one gradient bar per panel — this is it, no
              // inner region gets a second one.
              GradientTopBar(hue: hueForIndex(index)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const IconTile(icon: Icons.source_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            repo.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textTheme.titleSmall?.copyWith(
                              color: AppTokens.ink,
                            ),
                          ),
                          if (repo.now.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              repo.now,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.mono.copyWith(
                                color: AppTokens.inkSoft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(tone: _toneFor(state), label: _labelFor(state)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
