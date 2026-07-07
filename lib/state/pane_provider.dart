/// Riverpod state for a single session's live pane buffer.
///
/// [paneProvider] is a per-session-name family: on first watch for a given
/// `sessionName` it seeds the buffer via a one-shot REST
/// `GET /api/sessions/{name}/pane` call (through [bastionApiProvider]) and
/// subscribes to the `"pane:<name>"` WS topic (through
/// [bastionSocketProvider]), applying every decoded [PaneFrame] as it
/// arrives. Frames are keyed by `seq`: a frame whose `seq` is not strictly
/// greater than the last-applied `seq` is dropped as out-of-order/duplicate,
/// otherwise it replaces the buffer.
///
/// The family is `autoDispose` so the `"pane:<name>"` subscription is torn
/// down (an `unsubscribe` frame is sent) as soon as the last widget watching
/// a given session's pane stops watching it — the app should not keep a pane
/// stream alive for a session the operator has navigated away from.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_socket.dart` and `services/bastion_api.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/frame.dart';
import '../services/bastion_api.dart';
import '../services/bastion_socket.dart';
import 'sessions_provider.dart' show bastionApiProvider, bastionSocketProvider;

/// WS topic name for a given session's live pane stream (serve-api v0.2).
String paneTopic(String sessionName) => 'pane:$sessionName';

// ---------------------------------------------------------------------------
// Pane buffer state
// ---------------------------------------------------------------------------

/// Live pane buffer for one session: REST-seeded on first read, then kept
/// current by WS `pane` frames on the `"pane:<name>"` topic.
final paneProvider = StateNotifierProvider.autoDispose
    .family<PaneNotifier, List<String>, String>((ref, sessionName) {
      final socket = ref.watch(bastionSocketProvider);
      final api = ref.watch(bastionApiProvider);
      if (socket == null || api == null) {
        throw StateError(
          'paneProvider read before bastionSocketProvider/bastionApiProvider '
          'were set — the app shell must connect before mounting a pane view.',
        );
      }
      // NB: StateNotifierProvider disposes the returned notifier
      // automatically when the provider itself is disposed — do not also
      // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
      // twice.
      return PaneNotifier(sessionName: sessionName, socket: socket, api: api);
    });

/// Owns the `"pane:<name>"` topic subscription, REST seed, and `seq`-ordered
/// buffer for [paneProvider].
class PaneNotifier extends StateNotifier<List<String>> {
  // Named parameters socket/api map to private fields; initializing formals
  // cannot be used here because the public parameter names differ from the
  // private field names (e.g. `socket` → `_socket`).
  // ignore: prefer_initializing_formals
  PaneNotifier({
    required this.sessionName,
    required BastionSocket socket,
    required BastionApi api,
  }) : _socket = socket, // ignore: prefer_initializing_formals
       _api = api, // ignore: prefer_initializing_formals
       super(const []) {
    _seed();
    _socket.send(ClientFrames.subscribe(paneTopic(sessionName)));
    // Filter to this session's own pane frames first, then debounce
    // (trailing, ~150ms) — a rapid-fire burst of output frames (or fast pane
    // switching re-subscribing) collapses to the single latest buffer
    // instead of thrashing a rebuild per frame. Filtering before debouncing
    // keeps a burst on another session's pane from affecting this one, since
    // `_socket.frames` is a single shared broadcast stream across sessions.
    _sub = _socket.frames
        .where((frame) => frame is PaneFrame && frame.session == sessionName)
        .cast<PaneFrame>()
        .debounceTime(const Duration(milliseconds: 150))
        .listen(_onFrame);
  }

  final String sessionName;
  final BastionSocket _socket;
  final BastionApi _api;
  StreamSubscription<PaneFrame>? _sub;

  /// The `seq` of the last-applied WS `pane` frame, or `null` if none has
  /// been applied yet (the REST seed has no `seq` of its own).
  int? _lastSeq;

  /// `true` once the first WS `pane` frame has been applied — after that
  /// point the (possibly slower) REST seed must never overwrite newer WS
  /// state.
  bool _sawWsFrame = false;

  Future<void> _seed() async {
    try {
      final pane = await _api.getPane(sessionName);
      if (mounted && !_sawWsFrame) {
        state = pane.lines;
      }
    } catch (_) {
      // REST seed failure is non-fatal — the WS `pane` stream (once
      // subscribed) is the source of truth going forward.
    }
  }

  void _onFrame(PaneFrame frame) {
    final lastSeq = _lastSeq;
    if (lastSeq != null && frame.seq <= lastSeq) {
      // Out-of-order or duplicate frame — drop it, keep the newer buffer.
      return;
    }
    _sawWsFrame = true;
    _lastSeq = frame.seq;
    state = frame.lines;
  }

  @override
  void dispose() {
    _socket.send(ClientFrames.unsubscribe(paneTopic(sessionName)));
    _sub?.cancel();
    super.dispose();
  }
}
