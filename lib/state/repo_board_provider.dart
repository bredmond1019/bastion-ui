/// Riverpod state for the Repo Detail screen's typed block records
/// (`BU.13.C` task 1).
///
/// `RepoStatusDto` (`lib/models/repo_status_dto.dart`) carries `now`/
/// `next`/`blocked` and the `momentum*` fields as prose `String`s — there
/// is nothing structured on it for the restructured screen (`BU.13.C`) to
/// render. The typed per-block records (`BoardBlockDto`, grouped into
/// `BoardLaneDto`) live on `GET /api/board`, not `/api/repos/{name}/status`.
/// [repoBoardProvider] is the provider that fetches them for one repo.
///
/// ## Family, keyed by repo name
///
/// Mirrors `workflows_provider.dart`'s `repoWorkflowsProvider` family
/// pattern: one independent [BriefingSectionState] per repo name, so the
/// repo-detail screen for repo A never shares load/error state with repo
/// B's screen instance.
///
/// ## Source: `BoardDto.repos`, never `BoardDto.lanes`
///
/// The call is `getBoard(scope: 'project', repo: <name>, graph: true)`.
/// `BoardDto.repos` (a `List<RepoBoardDto>`) is populated for
/// `scope=project` and carries this one repo's own lane breakdown. The
/// aggregate `BoardDto.lanes` spans *every* in-scope repo under a
/// `project`-scope query and is the wrong source for a single repo's
/// detail screen — reading it here would silently include other repos'
/// blocks.
///
/// If the response's `repos` list has no entry whose `repo` matches the
/// requested name, that is an **empty state** (a repo with no blocks in
/// mev's board), not an error — [RepoBoardSectionNotifier] resolves a
/// missing match to an empty [BoardLaneDto] rather than throwing.
///
/// ## Independent per-section failure
///
/// Reuses [BriefingSectionState] / the loading→loaded/error state shape
/// from `briefing_provider.dart` (`BU.13.B`) rather than inventing a
/// parallel one, per the spec's "reuse, don't rebuild" note.
///
/// ## Root-scope only (D2)
///
/// [repoBoardProvider] is a plain top-level `.family` provider with no
/// screen-local override — a nested `ProviderScope` override is invisible
/// to routes pushed onto the app's `Navigator`, and repo detail is reached
/// exactly that way, mirroring `repoWorkflowsProvider` and
/// `briefingBoardProvider`.
///
/// ## The `graph: true` decision (spec Notes, deliberate)
///
/// This provider pays the `graph: true` cost on every open, same choice as
/// `briefingBoardProvider`. Reasoning: task 4 of this spec must render
/// `ready` (never derived from `unmetCount == 0`) and `dependentCount` per
/// block, and both fields are only present on the wire when `graph=1` was
/// requested — an ungraphed response has nothing for the readiness column
/// to show at all, which is a materially worse first paint than a slightly
/// slower one. Unlike the Briefing (a home surface hit on every app open),
/// repo detail is a drill-in the operator reaches deliberately, so the
/// per-open cost is paid far less often in practice; a two-phase fetch
/// (ungraphed first, re-rank once the graph arrives) would only reintroduce
/// the visible-reorder-under-the-operator's-thumb risk `briefing_provider
/// .dart` already rejected, for a screen with fewer rows where that
/// reorder would be even more noticeable. Single-shot, graph-on, wins here
/// too.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/board_dto.dart';
import '../services/bastion_api.dart';
import 'briefing_model.dart';
import 'briefing_provider.dart';
import 'sessions_provider.dart' show bastionApiProvider;

/// Per-repo typed board lanes, keyed by repo name.
///
/// Seeds on first watch via `GET /api/board?scope=project&repo=NAME
/// &graph=true` and resolves to the matching [RepoBoardDto]'s [BoardLaneDto]
/// out of the response's `repos` list — never the aggregate `lanes`.
final repoBoardProvider =
    StateNotifierProvider.family<
      RepoBoardSectionNotifier,
      BriefingSectionState<BoardLaneDto>,
      String
    >((ref, repoName) {
      final api = ref.watch(bastionApiProvider);
      if (api == null) {
        throw StateError(
          'repoBoardProvider read before bastionApiProvider was set — the '
          'app shell must connect before mounting the repo-detail screen.',
        );
      }
      return RepoBoardSectionNotifier(api, repoName);
    });

/// Fetches one repo's [BoardLaneDto] out of `GET /api/board?scope=project`
/// and exposes it as a [BriefingSectionState], reusing
/// [BriefingSectionNotifier]'s independent loading/loaded/error shape.
class RepoBoardSectionNotifier extends BriefingSectionNotifier<BoardLaneDto> {
  RepoBoardSectionNotifier(BastionApi api, String repoName)
    : super(() => _fetchRepoLanes(api, repoName));
}

/// `GET /api/board?scope=project&repo=<repoName>&graph=true`, resolved to
/// the [repoName]-matching [RepoBoardDto]'s lanes. A repo absent from the
/// response's `repos` list resolves to an empty [BoardLaneDto] (an empty
/// state), not an error — the request itself succeeded; mev simply has no
/// blocks recorded for this repo.
Future<BoardLaneDto> _fetchRepoLanes(BastionApi api, String repoName) async {
  final board = await api.getBoard(
    scope: 'project',
    repo: repoName,
    graph: true,
  );
  for (final repoBoard in board.repos) {
    if (repoBoard.repo == repoName) {
      return repoBoard.lanes;
    }
  }
  return const BoardLaneDto();
}
