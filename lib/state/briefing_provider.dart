/// Riverpod state for the Briefing screen (`BU.13.B` task 3) — composes
/// `GET /api/board`, `GET /api/attention`, and the existing live sessions
/// state ([sessionsProvider]) into [BriefingViewModel]
/// (`lib/state/briefing_model.dart`, task 1).
///
/// ## Independent per-section failure
///
/// The board and attention sections are fetched by two SEPARATE
/// [BriefingSectionNotifier]s, not one `Future.wait` — a `Future.wait`
/// fails whole the moment either call throws, which would blank the
/// section that actually succeeded. Each notifier owns its own
/// loading/loaded/error transition and is unaffected by the other's
/// outcome. [briefingViewModelProvider] only *combines* the three already-
/// independent states; it performs no fetching itself and cannot itself
/// fail.
///
/// The sessions section reuses [sessionsProvider] as-is (task 3's brief:
/// "the existing sessions state") rather than re-fetching — that notifier
/// already seeds via REST and self-heals via the `"sessions"` WS topic, and
/// treats a REST seed failure as non-fatal (falls back to WS), so it never
/// surfaces an error state of its own to compose here.
///
/// ## Root-scope only (D2)
///
/// [briefingBoardProvider], [briefingAttentionProvider], and
/// [briefingViewModelProvider] are plain top-level providers with no
/// screen-local override, mirroring `sessions_provider.dart`'s
/// [bastionApiProvider]/[bastionSocketProvider] pattern — a nested
/// `ProviderScope` override is invisible to routes pushed onto the app's
/// `Navigator`, and the Briefing is reached exactly that way (task 2).
///
/// ## The `graph=true` cost decision
///
/// `dependent_count` — the blast-radius figure gate ranking (task 1) sorts
/// on — is only populated when `/api/board` is called with `?graph=true`,
/// and that flag roughly doubles the endpoint's wall-clock on the live
/// corpus (spec Context Pointers). This provider chooses to **pay that
/// cost on every load**, i.e. [briefingBoardProvider] always calls
/// `api.getBoard(graph: true)`, rather than fetching an ungraphed board
/// first and a graphed one after.
///
/// Reasoning: the Briefing's entire premise (principle 2, "rank by
/// consequence") is that operator gates are ordered by how much unblocks
/// when they clear. An ungraphed board cannot rank gates at all — every
/// `dependent_count` would read `null` and every gate would tie at "unknown
/// blast radius," which is a materially worse first paint than a slightly
/// slower one. A two-phase fetch (fast ungraphed board, then a slower
/// re-rank once the graph arrives) would avoid the latency but reintroduces
/// exactly the two-source-of-truth risk task 1's doc comment warns about
/// for the header counts, twice over — the gate list would visibly
/// reorder under the operator's thumb. Simplicity and rank stability win
/// this trade for a screen whose whole job is answering one question
/// correctly, not answering it fast and then correcting itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attention_dto.dart';
import '../models/board_dto.dart';
import '../models/session_dto.dart';
import '../services/bastion_api.dart';
import 'briefing_model.dart';
import 'sessions_provider.dart' show bastionApiProvider, sessionsProvider;

// ---------------------------------------------------------------------------
// Generic per-section fetch notifier
// ---------------------------------------------------------------------------

/// Renders a caught exception into a short, display-ready message.
///
/// Kept intentionally simple (type name + message) — the Briefing's inline
/// error states (task 6) own presentation; this only guarantees a non-empty,
/// non-stack-trace string.
String describeBriefingSectionError(Object error) {
  if (error is FatalAuthError) {
    return 'Authentication failed: ${error.payload.message ?? error.payload.code}';
  }
  if (error is ApiError) {
    return 'Server error (${error.statusCode})';
  }
  return error.toString();
}

/// Owns one independently-fetched Briefing section: fetches [_fetch] once on
/// construction, and re-fetches only on an explicit [reload].
///
/// Generic over the decoded payload type `T` so [briefingBoardProvider] and
/// [briefingAttentionProvider] share one implementation rather than two
/// hand-copied notifiers.
class BriefingSectionNotifier<T>
    extends StateNotifier<BriefingSectionState<T>> {
  BriefingSectionNotifier(this._fetch) : super(const BriefingSectionLoading()) {
    _load();
  }

  final Future<T> Function() _fetch;

  Future<void> _load() async {
    if (mounted) state = const BriefingSectionLoading();
    try {
      final data = await _fetch();
      if (mounted) state = BriefingSectionLoaded<T>(data);
    } catch (e) {
      if (mounted) {
        state = BriefingSectionError<T>(describeBriefingSectionError(e));
      }
    }
  }

  /// Unconditionally re-fetch this section, regardless of its current
  /// state. Callers wanting to refresh only failed sections should use
  /// [refreshFailedBriefingSections] instead of calling this directly on
  /// every section.
  Future<void> reload() => _load();
}

// ---------------------------------------------------------------------------
// Board + attention sections
// ---------------------------------------------------------------------------

/// `GET /api/board?graph=true` section — see the `graph=true` cost decision
/// in this file's doc comment.
final briefingBoardProvider =
    StateNotifierProvider<
      BriefingSectionNotifier<BoardDto>,
      BriefingSectionState<BoardDto>
    >((ref) {
      final api = ref.watch(bastionApiProvider);
      if (api == null) {
        throw StateError(
          'briefingBoardProvider read before bastionApiProvider was set — '
          'the app shell must connect before mounting the Briefing.',
        );
      }
      return BriefingSectionNotifier<BoardDto>(() => api.getBoard(graph: true));
    });

/// `GET /api/attention` section.
final briefingAttentionProvider =
    StateNotifierProvider<
      BriefingSectionNotifier<AttentionDto>,
      BriefingSectionState<AttentionDto>
    >((ref) {
      final api = ref.watch(bastionApiProvider);
      if (api == null) {
        throw StateError(
          'briefingAttentionProvider read before bastionApiProvider was set '
          '— the app shell must connect before mounting the Briefing.',
        );
      }
      return BriefingSectionNotifier<AttentionDto>(() => api.getAttention());
    });

// ---------------------------------------------------------------------------
// Sessions section (reuses the existing live sessions state)
// ---------------------------------------------------------------------------

/// Wraps [sessionsProvider]'s plain `List<SessionDto>` as a
/// [BriefingSectionState] so [briefingViewModelProvider] can compose it
/// uniformly with the board/attention sections. Always [BriefingSectionLoaded]
/// — [sessionsProvider] never surfaces a REST failure as an error state (it
/// falls back to the WS `"sessions"` snapshot instead), so there is no
/// separate error branch to model here.
final briefingSessionsSectionProvider =
    Provider<BriefingSectionState<List<SessionDto>>>((ref) {
      final sessions = ref.watch(sessionsProvider);
      return BriefingSectionLoaded<List<SessionDto>>(sessions);
    });

// ---------------------------------------------------------------------------
// Combined view model
// ---------------------------------------------------------------------------

/// The full [BriefingViewModel] for the screen — a pure combination of the
/// three independent section providers above. Performs no fetching itself;
/// each constituent section is responsible for its own load/error, so this
/// provider can never itself fail or blank the screen.
final briefingViewModelProvider = Provider<BriefingViewModel>((ref) {
  final board = ref.watch(briefingBoardProvider);
  final attention = ref.watch(briefingAttentionProvider);
  final sessions = ref.watch(briefingSessionsSectionProvider);
  return BriefingViewModel(
    board: board,
    attention: attention,
    sessions: sessions,
  );
});

// ---------------------------------------------------------------------------
// Refresh — re-fetch only what failed
// ---------------------------------------------------------------------------

/// Re-fetches only the sections currently in an error state, leaving loaded
/// (or still-loading) sections untouched. A pull-to-refresh that always
/// re-fetched all three would re-pay the (roughly double) `graph=true`
/// board cost even when the board already loaded fine and only attention
/// failed.
///
/// Takes a [ProviderContainer] rather than a [Ref]/`WidgetRef` so it works
/// identically from a test's own container and from screen code (via
/// `ProviderScope.containerOf(context, listen: false)`) without two
/// parallel implementations.
Future<void> refreshFailedBriefingSections(ProviderContainer container) async {
  final reloads = <Future<void>>[];

  if (container.read(briefingBoardProvider) is BriefingSectionError<BoardDto>) {
    reloads.add(container.read(briefingBoardProvider.notifier).reload());
  }
  if (container.read(briefingAttentionProvider)
      is BriefingSectionError<AttentionDto>) {
    reloads.add(container.read(briefingAttentionProvider.notifier).reload());
  }

  await Future.wait(reloads);
}
