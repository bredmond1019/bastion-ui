/// Riverpod state for the `needs_input` session event stream.
///
/// Filters the shared [bastionSocketProvider] frame stream (see
/// `sessions_provider.dart`) for [EventFrame]s where `event == "needs_input"`,
/// keyed by session name. Two things consume this:
///   - the sessions-list screen (`BU.1.A` Task 5) — a per-session flag badge,
///     driven by [needsInputProvider]'s `Set<String>` state.
///   - the local-notification service (`BU.1.A` Task 7) — fires once per
///     event, driven by [needsInputEventsProvider]'s raw event stream.
///
/// This file is Flutter/riverpod-facing (not pure Dart).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/frame.dart';
import 'sessions_provider.dart' show bastionSocketProvider;

/// The WS `event.event` value that signals a session is blocked waiting on
/// operator input (serve-api v0.2 §8, rising-edge debounced server-side).
const needsInputEvent = 'needs_input';

// ---------------------------------------------------------------------------
// Raw filtered event stream
// ---------------------------------------------------------------------------

/// Broadcast stream of `needs_input` [EventFrame]s decoded from the shared
/// socket. Each read constructs a fresh filtered view over the same
/// underlying broadcast stream, so independent listeners (badge state,
/// notification service) never steal events from one another.
final needsInputEventsProvider = Provider<Stream<EventFrame>>((ref) {
  final socket = ref.watch(bastionSocketProvider);
  if (socket == null) {
    throw StateError(
      'needsInputEventsProvider read before bastionSocketProvider was set — '
      'the app shell must connect before watching needs-input events.',
    );
  }
  return socket.frames
      .where((frame) => frame is EventFrame && frame.event == needsInputEvent)
      .cast<EventFrame>();
});

// ---------------------------------------------------------------------------
// Derived per-session flag state
// ---------------------------------------------------------------------------

/// Set of session names currently flagged as needing input.
///
/// A session is added when a `needs_input` event arrives for it; consumers
/// (e.g. the detail screen, once the operator has viewed/acted on the
/// prompt) call [NeedsInputNotifier.clear] to drop the flag.
final needsInputProvider =
    StateNotifierProvider<NeedsInputNotifier, Set<String>>((ref) {
      // NB: StateNotifierProvider disposes the returned notifier
      // automatically when the provider itself is disposed — do not also
      // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
      // twice.
      return NeedsInputNotifier(ref.watch(needsInputEventsProvider));
    });

/// Tracks the current set of sessions with a pending `needs_input` flag.
class NeedsInputNotifier extends StateNotifier<Set<String>> {
  NeedsInputNotifier(Stream<EventFrame> events) : super(const {}) {
    _sub = events.listen(_onEvent);
  }

  StreamSubscription<EventFrame>? _sub;

  void _onEvent(EventFrame frame) {
    if (state.contains(frame.session)) return;
    state = {...state, frame.session};
  }

  /// Clear the pending flag for [session], if set.
  void clear(String session) {
    if (!state.contains(session)) return;
    state = {...state}..remove(session);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
