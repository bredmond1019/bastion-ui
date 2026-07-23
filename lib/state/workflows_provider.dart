/// Riverpod state for a single repo's status + workflow list, plus the
/// shared `workflow_done` WS event stream.
///
/// [workflowDoneEventsProvider] mirrors `events_provider.dart`'s
/// `needsInputEventsProvider` pattern: it filters the shared
/// [bastionSocketProvider] frame stream for [EventFrame]s where
/// `event == "workflow_done"` (repo-scoped events carry `session: ""`; the
/// repo name lives in `extra['repo']`, per `bastion/docs/serve-api.md` v0.3
/// §11/§8.2 — no new frame kind is decoded).
///
/// [repoWorkflowsProvider] is a `.family` keyed by repo name: on first watch
/// it seeds via `GET /api/repos/{name}/status` + `GET
/// /api/repos/{name}/workflows` (through [bastionApiProvider], shared with
/// `sessions_provider.dart`), then auto-refetches whenever a matching
/// `workflow_done` event (`extra['repo'] == name`) arrives — this is what
/// flips a repo's in-flight indicator on the dashboard and repo-detail
/// screens without a manual refresh.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_api.dart` and `models/frame.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/frame.dart';
import '../models/repo_status_dto.dart';
import '../services/bastion_api.dart';
import 'sessions_provider.dart' show bastionApiProvider, bastionSocketProvider;

/// The WS `event.event` value that signals an SDLC workflow for a repo has
/// finished (serve-api v0.3 §8.2).
const workflowDoneEvent = 'workflow_done';

// ---------------------------------------------------------------------------
// Raw filtered event stream
// ---------------------------------------------------------------------------

/// Broadcast stream of `workflow_done` [EventFrame]s decoded from the shared
/// socket. Each read constructs a fresh filtered view over the same
/// underlying broadcast stream, so independent listeners (per-repo state,
/// the notification service) never steal events from one another.
///
/// This raw stream is intentionally left undebounced here — it fans out to
/// every repo's [repoWorkflowsProvider] family member. Debouncing it at this
/// shared layer would let a burst of events for repo B swallow a concurrent
/// event for repo A (rxdart's `debounceTime` only re-emits the latest value
/// on a single shared stream). Each family member instead filters to its own
/// repo *before* debouncing (see [repoWorkflowsProvider]), so the ~150ms
/// window only coalesces same-repo refresh triggers.
final workflowDoneEventsProvider = Provider<Stream<EventFrame>>((ref) {
  final socket = ref.watch(bastionSocketProvider);
  if (socket == null) {
    throw StateError(
      'workflowDoneEventsProvider read before bastionSocketProvider was '
      'set — the app shell must connect before watching workflow-done '
      'events.',
    );
  }
  return socket.frames
      .where((frame) => frame is EventFrame && frame.event == workflowDoneEvent)
      .cast<EventFrame>();
});

// ---------------------------------------------------------------------------
// Per-repo status + workflow state
// ---------------------------------------------------------------------------

/// Snapshot of a single repo's parsed status + workflow list.
final class RepoWorkflowsState {
  final RepoStatusDto? status;
  final List<WorkflowStateDto> workflows;
  final bool loading;

  const RepoWorkflowsState({
    this.status,
    this.workflows = const [],
    this.loading = true,
  });

  RepoWorkflowsState copyWith({
    RepoStatusDto? status,
    List<WorkflowStateDto>? workflows,
    bool? loading,
  }) {
    return RepoWorkflowsState(
      status: status ?? this.status,
      workflows: workflows ?? this.workflows,
      loading: loading ?? this.loading,
    );
  }
}

/// Per-repo status + workflow state, keyed by repo name.
///
/// Seeds on first watch and auto-refetches on a matching `workflow_done`
/// event for that repo.
final repoWorkflowsProvider =
    StateNotifierProvider.family<
      RepoWorkflowsNotifier,
      RepoWorkflowsState,
      String
    >((ref, repoName) {
      final api = ref.watch(bastionApiProvider);
      if (api == null) {
        throw StateError(
          'repoWorkflowsProvider read before bastionApiProvider was set — the '
          'app shell must connect before mounting the repo-detail screen.',
        );
      }
      // Filter to this repo's own `workflow_done` events first, then debounce
      // (trailing, ~150ms) — filtering before debouncing keeps a burst of
      // events for other repos from swallowing this repo's refresh trigger
      // (see the note on [workflowDoneEventsProvider]).
      final events = ref
          .watch(workflowDoneEventsProvider)
          .where((frame) => frame.extra['repo'] == repoName)
          .debounceTime(const Duration(milliseconds: 150));
      // NB: StateNotifierProvider disposes the returned notifier automatically
      // when the provider itself is disposed — do not also register
      // `ref.onDispose(notifier.dispose)` here, or dispose() runs twice.
      return RepoWorkflowsNotifier(
        api: api,
        repoName: repoName,
        events: events,
      );
    });

/// Owns the REST seed + `workflow_done` subscription for
/// [repoWorkflowsProvider].
class RepoWorkflowsNotifier extends StateNotifier<RepoWorkflowsState> {
  // Named parameter api maps to private field _api; initializing formals
  // cannot be used here because the public parameter name differs from the
  // private field name.
  // ignore: prefer_initializing_formals
  RepoWorkflowsNotifier({
    required BastionApi api,
    required this.repoName,
    required Stream<EventFrame> events,
  }) : _api = api, // ignore: prefer_initializing_formals
       super(const RepoWorkflowsState()) {
    _refresh();
    _sub = events.listen(_onEvent);
  }

  final BastionApi _api;
  final String repoName;
  StreamSubscription<EventFrame>? _sub;

  /// Re-fetch this repo's status + workflow list from `GET
  /// /api/repos/{name}/status` and `GET /api/repos/{name}/workflows`.
  ///
  /// Failures are non-fatal — the previous state is left in place (minus the
  /// `loading` flag) so a transient network blip doesn't blank an
  /// already-rendered screen.
  Future<void> _refresh() async {
    // Fetch both legs independently — a 404/C002 on one (e.g. a
    // registered-but-status-less repo) must not reject the other. Each leg
    // applies its own value on success and leaves the prior state in place
    // on failure; `loading` is cleared once both have settled regardless of
    // outcome.
    final statusFuture = _api
        .getRepoStatus(repoName)
        .then<RepoStatusDto?>((v) => v)
        .catchError((_) => null);
    final workflowsFuture = _api
        .getRepoWorkflows(repoName)
        .then<List<WorkflowStateDto>?>((v) => v)
        .catchError((_) => null);
    final statusResult = await statusFuture;
    final workflowsResult = await workflowsFuture;
    if (!mounted) return;
    state = state.copyWith(
      status: statusResult,
      workflows: workflowsResult,
      loading: false,
    );
  }

  void _onEvent(EventFrame frame) {
    if (frame.extra['repo'] != repoName) return;
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
