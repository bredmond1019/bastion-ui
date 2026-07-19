/// Riverpod state for the live sessions list.
///
/// [sessionsProvider] seeds the list via a one-shot REST `GET /api/sessions`
/// call (through [bastionApiProvider]) and then keeps it live by subscribing
/// to the `"sessions"` WS topic (through [bastionSocketProvider]) and
/// applying every decoded [SessionsFrame] snapshot as it arrives.
///
/// [bastionSocketProvider] and [bastionApiProvider] are shared injection
/// points (also used by `pane_provider.dart` and `events_provider.dart`) —
/// mutable [StateProvider]s that start `null` and are set once (via
/// `ref.read(provider.notifier).state = value`) by the app shell once a
/// connection is live. They are plain [StateProvider]s (not values requiring
/// a nested `ProviderScope` override) specifically so a value set anywhere
/// under the app's single root `ProviderScope` is visible everywhere in the
/// widget tree — including routes pushed onto the app's `Navigator`, which
/// sits *above* any nested override scope a screen might otherwise try to
/// create. Providers that depend on them (e.g. [sessionsProvider]) throw a
/// clear [StateError] if read before a value is set, so a missing wire-up
/// still fails loudly instead of silently no-op'ing.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_socket.dart` and `services/bastion_api.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/frame.dart';
import '../models/session_dto.dart';
import '../services/bastion_api.dart';
import '../services/bastion_socket.dart';
import '../state/connection_provider.dart' show ConnectionStatus;

/// WS topic name for the live sessions snapshot stream (serve-api v0.2).
const sessionsTopic = 'sessions';

// ---------------------------------------------------------------------------
// Shared injection points
// ---------------------------------------------------------------------------

/// Injection point for the live [BastionSocket] shared across session/pane/
/// event state.
///
/// `null` until the app shell sets it (`ref.read(bastionSocketProvider.notifier)
/// .state = socket`) once a connection is live.
final bastionSocketProvider = StateProvider<BastionSocket?>((ref) => null);

/// Injection point for the [BastionApi] REST client used to seed session
/// and pane state before the first WS snapshot arrives.
///
/// `null` until the app shell sets it, mirroring [bastionSocketProvider].
final bastionApiProvider = StateProvider<BastionApi?>((ref) => null);

// ---------------------------------------------------------------------------
// Sessions list state
// ---------------------------------------------------------------------------

/// Live list of sessions: REST-seeded on first read, then kept current by
/// WS `sessions` frames on the `"sessions"` topic.
final sessionsProvider = StateNotifierProvider<SessionsNotifier, List<SessionDto>>((
  ref,
) {
  final socket = ref.watch(bastionSocketProvider);
  final api = ref.watch(bastionApiProvider);
  if (socket == null || api == null) {
    throw StateError(
      'sessionsProvider read before bastionSocketProvider/bastionApiProvider '
      'were set — the app shell must connect before mounting the sessions list.',
    );
  }
  // NB: StateNotifierProvider disposes the returned notifier
  // automatically when the provider itself is disposed — do not also
  // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
  // twice.
  return SessionsNotifier(socket: socket, api: api);
});

/// Owns the `"sessions"` topic subscription and REST seed for
/// [sessionsProvider].
class SessionsNotifier extends StateNotifier<List<SessionDto>> {
  // Named parameters socket/api map to private fields; initializing formals
  // cannot be used here because the public parameter names differ from the
  // private field names (e.g. `socket` → `_socket`).
  // ignore: prefer_initializing_formals
  SessionsNotifier({required BastionSocket socket, required BastionApi api})
    : _socket = socket, // ignore: prefer_initializing_formals
      _api = api, // ignore: prefer_initializing_formals
      super(const []) {
    _seed();
    _socket.send(ClientFrames.subscribe(sessionsTopic));
    // Filter to `sessions` snapshots first, then debounce (trailing,
    // ~150ms) — a flood of snapshot frames (e.g. many sessions churning at
    // once) collapses to the single latest list instead of thrashing a
    // rebuild per frame.
    _sub = _socket.frames
        .where((frame) => frame is SessionsFrame)
        .cast<SessionsFrame>()
        .debounceTime(const Duration(milliseconds: 150))
        .listen(_onFrame);
    // Re-run the REST seed on every reconnect (transition *into* `connected`
    // after the socket's first connect) — the socket itself replays the WS
    // `subscribe` frame (see bastion_socket.dart), but the REST buffer this
    // notifier seeded before the drop can now be stale, so it needs a fresh
    // `_seed()` too. The first connect must NOT double-seed (the ctor above
    // already called `_seed()` once), hence the `_everConnected` gate — seeded
    // from the socket's *current* status at subscribe time, since the socket
    // (and its first connect) normally already exists before this notifier
    // is constructed (`sessionsProvider` throws if read before the socket is
    // set/connected), so any "connected" transition this stream observes is
    // necessarily a reconnect in that common case.
    _everConnected = _socket.status == ConnectionStatus.connected;
    _statusSub = _socket.statusStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        if (_everConnected) {
          _seed();
        }
        _everConnected = true;
      }
    });
  }

  final BastionSocket _socket;
  final BastionApi _api;
  StreamSubscription<SessionsFrame>? _sub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  /// `true` once the socket has completed at least one successful connect —
  /// guards against re-seeding on the very first connect (already handled by
  /// the constructor's direct `_seed()` call). Set from the socket's current
  /// status at construction time (see the constructor body).
  bool _everConnected = false;

  /// `true` once the first WS `sessions` snapshot has been applied — after
  /// that point the (possibly slower) REST seed must never overwrite newer
  /// WS state.
  bool _sawWsSnapshot = false;

  Future<void> _seed() async {
    try {
      final sessions = await _api.getSessions();
      if (mounted && !_sawWsSnapshot) {
        state = sessions;
      }
    } catch (_) {
      // REST seed failure is non-fatal — the WS `sessions` snapshot (once
      // subscribed) is the source of truth going forward.
    }
  }

  void _onFrame(SessionsFrame frame) {
    _sawWsSnapshot = true;
    state = frame.sessions;
  }

  @override
  void dispose() {
    _socket.send(ClientFrames.unsubscribe(sessionsTopic));
    _sub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
