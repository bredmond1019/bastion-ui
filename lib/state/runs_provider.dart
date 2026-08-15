/// Riverpod state for the live runs list (`BU.13.E` task 4).
///
/// [runsProvider] seeds the list via a one-shot REST `GET /api/runs` call
/// (through [bastionApiProvider], shared with `sessions_provider.dart`) and
/// then keeps it live by subscribing to the bearer-authed `"runs"` WS topic
/// (through [bastionSocketProvider]) and applying each `event
/// {run_transition}` frame as it arrives — so a run started elsewhere
/// changes state on the phone with no pull-to-refresh.
///
/// ## Reuse, not a second mechanism
///
/// `bastion_socket.dart` already tracks active `subscribe`/`unsubscribe`
/// topics and replays them automatically on reconnect
/// (`bastion_socket.dart:313-316`, exercised by
/// `test/services/reconnect_resubscribe_test.dart`). This notifier sends
/// `subscribe`/`unsubscribe` exactly once each (constructor / [dispose]) via
/// the existing [ClientFrames] encoders and lets the socket own replay — it
/// does not re-subscribe itself on a reconnect.
///
/// ## `run_transition` decoding — no new [BastionFrame] kind
///
/// `run_transition` (and `run_stream_status`) arrive as ordinary `"event"`
/// frames per serve-api.md §8.3/§14 — `frame.dart`'s existing `event` case
/// already decodes `{session, event, ...payload}` into [EventFrame] with
/// the full payload carried in [EventFrame.extra]. This mirrors
/// `workflows_provider.dart`'s `workflow_done` filtering; no new frame type
/// is needed.
///
/// ## Trap 1 — unsubscribe on dispose
///
/// The server starts its runs poller on the FIRST `"runs"` subscriber and
/// stops it on the LAST — a notifier that never releases leaves the server
/// polling forever, an invisible, cumulative cost. [dispose] always sends
/// `ClientFrames.unsubscribe(runsTopic)`.
///
/// ## Trap 2 — `terminal` is lifecycle-terminal, not wire-terminal
///
/// `run_transition.terminal` means the run left `LiveStateStore`'s live map
/// (serve-api.md §8.3, §14) — the OPPOSITE of the embedded engine's own
/// wire-terminal flag. A suspended run reports `status: "suspended",
/// terminal: false` and STAYS in [state]. Only `terminal: true` removes a
/// run from [state] (mirroring what a fresh `GET /api/runs` would no
/// longer return, since that route is scoped to `list_active()`).
///
/// ## Trap 3 — empty is a valid state, never an error
///
/// A `200 []` response (no engine mounted) seeds [state] to an empty list
/// via the normal REST-seed path; this notifier never treats it as a
/// failure. Rendering the explanatory empty state is the runs screen's job
/// (task 5), not this provider's.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_api.dart`, `services/bastion_socket.dart`, and
/// `models/frame.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/frame.dart';
import '../models/run_dto.dart';
import '../services/bastion_api.dart';
import '../services/bastion_socket.dart';
import 'sessions_provider.dart' show bastionApiProvider, bastionSocketProvider;

/// WS topic name for the live runs push stream (serve-api.md v0.23, §6/§14).
const runsTopic = 'runs';

/// The `event.event` value for a live run's aggregate-status push
/// (serve-api.md §8.3).
const runTransitionEvent = 'run_transition';

/// Live list of runs: REST-seeded on first read, then kept current by
/// pushed `run_transition` frames on the bearer-authed `"runs"` WS topic.
final runsProvider = StateNotifierProvider<RunsNotifier, List<RunSummaryDto>>((
  ref,
) {
  final socket = ref.watch(bastionSocketProvider);
  final api = ref.watch(bastionApiProvider);
  if (socket == null || api == null) {
    throw StateError(
      'runsProvider read before bastionSocketProvider/bastionApiProvider '
      'were set — the app shell must connect before mounting the runs '
      'screen.',
    );
  }
  // NB: StateNotifierProvider disposes the returned notifier
  // automatically when the provider itself is disposed — do not also
  // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
  // twice (the trap already documented in `repos_provider.dart`).
  return RunsNotifier(socket: socket, api: api);
});

/// Owns the `"runs"` topic subscription and REST seed for [runsProvider].
class RunsNotifier extends StateNotifier<List<RunSummaryDto>> {
  // Named parameters socket/api map to private fields; initializing formals
  // cannot be used here because the public parameter names differ from the
  // private field names (e.g. `socket` → `_socket`).
  // ignore: prefer_initializing_formals
  RunsNotifier({required BastionSocket socket, required BastionApi api})
    : _socket = socket, // ignore: prefer_initializing_formals
      _api = api, // ignore: prefer_initializing_formals
      super(const []) {
    _seed();
    _socket.send(ClientFrames.subscribe(runsTopic));
    _sub = _socket.frames
        .where(
          (frame) => frame is EventFrame && frame.event == runTransitionEvent,
        )
        .cast<EventFrame>()
        .listen(_onTransition);
  }

  final BastionSocket _socket;
  final BastionApi _api;
  StreamSubscription<EventFrame>? _sub;

  /// Re-fetch the runs list from `GET /api/runs`.
  ///
  /// Failures are non-fatal — the previous state is left in place; the live
  /// `"runs"` WS subscription (once established) is the source of truth
  /// going forward. An empty list is a valid, expected success (no engine
  /// mounted), never treated as an error.
  Future<void> _seed() async {
    try {
      final runs = await _api.getRuns();
      if (mounted) {
        state = runs;
      }
    } catch (_) {
      // Non-fatal: keep the previously-seeded list.
    }
  }

  /// Applies one `event{run_transition}` frame (serve-api.md §8.3) to
  /// [state].
  ///
  /// `terminal: true` means lifecycle-terminal (the run left
  /// `list_active()`) and removes the run from [state] — mirroring what a
  /// fresh REST fetch would no longer return. Every other status,
  /// including `"suspended"`, updates the matching run (or appends a new
  /// one) and leaves it in [state] as live. A frame missing `run_id` or
  /// `status` is ignored rather than corrupting state.
  void _onTransition(EventFrame frame) {
    final runId = frame.extra['run_id'];
    final status = frame.extra['status'];
    if (runId is! String || status is! String) return;
    final terminal = frame.extra['terminal'] == true;
    final specSlug = frame.extra['spec_slug'];

    final index = state.indexWhere((r) => r.runId == runId);

    if (terminal) {
      if (index == -1) return;
      final next = [...state]..removeAt(index);
      state = next;
      return;
    }

    final previous = index == -1 ? null : state[index];
    final updated = RunSummaryDto(
      runId: runId,
      status: status,
      workflowType: previous?.workflowType,
      specSlug: specSlug is String ? specSlug : previous?.specSlug,
      startedAt: previous?.startedAt,
      updatedAt: previous?.updatedAt,
      repo: previous?.repo,
    );

    final next = [...state];
    if (index == -1) {
      next.add(updated);
    } else {
      next[index] = updated;
    }
    state = next;
  }

  @override
  void dispose() {
    _socket.send(ClientFrames.unsubscribe(runsTopic));
    _sub?.cancel();
    super.dispose();
  }
}
