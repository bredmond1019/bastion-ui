/// Riverpod state for the live sessions list.
///
/// [sessionsProvider] seeds the list via a one-shot REST `GET /api/sessions`
/// call (through [bastionApiProvider]) and then keeps it live by subscribing
/// to the `"sessions"` WS topic (through [bastionSocketProvider]) and
/// applying every decoded [SessionsFrame] snapshot as it arrives.
///
/// [bastionSocketProvider] and [bastionApiProvider] are shared injection
/// points (also used by `pane_provider.dart` and `events_provider.dart`) —
/// callers (the app shell) MUST override them with live, already-connected
/// instances before any provider that depends on them is read. They throw
/// [UnimplementedError] by default so a missing override fails loudly
/// instead of silently no-op'ing.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_socket.dart` and `services/bastion_api.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/frame.dart';
import '../models/session_dto.dart';
import '../services/bastion_api.dart';
import '../services/bastion_socket.dart';

/// WS topic name for the live sessions snapshot stream (serve-api v0.2).
const sessionsTopic = 'sessions';

// ---------------------------------------------------------------------------
// Shared injection points
// ---------------------------------------------------------------------------

/// Injection point for the live [BastionSocket] shared across session/pane/
/// event state.
///
/// Must be overridden (e.g. in the app's root `ProviderScope`) with a real,
/// connected instance before any dependent provider is read.
final bastionSocketProvider = Provider<BastionSocket>((ref) {
  throw UnimplementedError(
    'bastionSocketProvider has no override — wire a live, connected '
    'BastionSocket instance into the ProviderScope before reading '
    'session/pane/event state.',
  );
});

/// Injection point for the [BastionApi] REST client used to seed session
/// and pane state before the first WS snapshot arrives.
///
/// Must be overridden (e.g. in the app's root `ProviderScope`) with a real
/// instance before any dependent provider is read.
final bastionApiProvider = Provider<BastionApi>((ref) {
  throw UnimplementedError(
    'bastionApiProvider has no override — wire a live BastionApi instance '
    'into the ProviderScope before reading session/pane state.',
  );
});

// ---------------------------------------------------------------------------
// Sessions list state
// ---------------------------------------------------------------------------

/// Live list of sessions: REST-seeded on first read, then kept current by
/// WS `sessions` frames on the `"sessions"` topic.
final sessionsProvider =
    StateNotifierProvider<SessionsNotifier, List<SessionDto>>((ref) {
      // NB: StateNotifierProvider disposes the returned notifier
      // automatically when the provider itself is disposed — do not also
      // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
      // twice.
      return SessionsNotifier(
        socket: ref.watch(bastionSocketProvider),
        api: ref.watch(bastionApiProvider),
      );
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
    _sub = _socket.frames.listen(_onFrame);
  }

  final BastionSocket _socket;
  final BastionApi _api;
  StreamSubscription<BastionFrame>? _sub;

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

  void _onFrame(BastionFrame frame) {
    if (frame is SessionsFrame) {
      _sawWsSnapshot = true;
      state = frame.sessions;
    }
  }

  @override
  void dispose() {
    _socket.send(ClientFrames.unsubscribe(sessionsTopic));
    _sub?.cancel();
    super.dispose();
  }
}
