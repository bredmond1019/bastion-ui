/// Shared test seam for the e2e coverage tests (BU.7.B/C, BU.8.B).
///
/// This is a plain library (not tagged `e2e`) so it can be imported by both
/// the gating unit tests in `e2e_support_test.dart` and the non-gating
/// `@Tags(['e2e'])` coverage tests that drive a real `bastion serve`. It
/// exports:
///   - [tmuxAvailable] — a self-skip guard for tests that need a real tmux
///     binary on PATH.
///   - [subscribeAndCollect] — subscribe-and-collect N decoded
///     `BastionFrame`s from a `BastionSocket`.
///   - [withManagedSession] — create-yield-cleanup around
///     `BastionApi.createSession`/`deleteSession`.
///   - [collectEvents] — collect N decoded `EventFrame`s matching a given
///     `event` name from a `BastionSocket`'s shared broadcast frame stream
///     (no `subscribe` frame needed — `workflow_done` and other `event`
///     frames are broadcast to all connected clients with no topic gate).
///   - [writeFixtureFlowState] — write a minimal valid
///     `sdlc-flow-state.json` fixture file under a fixture repo's
///     `planning/<specSlug>/sdlc/` directory (BU.8.B).
///   - [collectFrames] — collect N decoded frames matching an arbitrary
///     predicate (no `subscribe` sent), for frames with no subscribe-topic
///     (e.g. `error`) or already-active subscriptions (BU.9.D/E).
///   - [awaitStatus] — await a `BastionSocket` reaching a given
///     `ConnectionStatus` (BU.9.B/D).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
import 'package:bastion_ui/state/connection_provider.dart'
    show ConnectionStatus;
import 'package:bastion_ui/state/pane_provider.dart' show paneTopic;

/// Returns whether the `tmux` binary is resolvable on PATH.
///
/// Uses a synchronous, non-throwing probe: runs `tmux -V` and treats any
/// exception (binary missing, `ProcessException`, etc.) as "not available"
/// rather than letting it propagate. Mirrors the skip-guard intent of
/// [BastionServeHarness]'s binary-absent check.
bool tmuxAvailable() {
  try {
    final result = Process.runSync('tmux', ['-V']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Returns whether [frame] belongs to [topic] (the `"sessions"` or
/// `"pane:<name>"` subscribe-topic convention from `pane_provider.dart`).
///
/// `pane` frames carry their own `session` field in the payload, so a
/// `"pane:<name>"` topic is matched by comparing the frame's `session`
/// against the name embedded in the topic (via [paneTopic]'s convention)
/// rather than by string-matching `frame.kind` alone — this keeps the
/// predicate correct even if other kinds are ever pushed on the same topic.
bool _matchesTopic(BastionFrame frame, String topic) {
  if (topic == 'sessions') {
    return frame is SessionsFrame;
  }
  if (frame is PaneFrame) {
    return paneTopic(frame.session) == topic;
  }
  return false;
}

/// Subscribes to [topic] on [socket] and resolves with the next [count]
/// decoded [BastionFrame]s that belong to it.
///
/// Listens on the shared broadcast [BastionSocket.frames] stream and
/// registers the collection **before** sending the `subscribe` frame, so no
/// frame delivered in response to the subscribe can be lost to a
/// subscribe-then-listen race. Throws a [TimeoutException] (tearing down the
/// subscription first) if fewer than [count] matching frames arrive within
/// [timeout].
Future<List<BastionFrame>> subscribeAndCollect(
  BastionSocket socket, {
  required String topic,
  required int count,
  required Duration timeout,
}) {
  final collected = <BastionFrame>[];
  final completer = Completer<List<BastionFrame>>();
  late final StreamSubscription<BastionFrame> sub;
  Timer? timer;

  Future<void> teardown() async {
    timer?.cancel();
    await sub.cancel();
  }

  sub = socket.frames.listen((frame) {
    if (completer.isCompleted) return;
    if (!_matchesTopic(frame, topic)) return;
    collected.add(frame);
    if (collected.length >= count) {
      unawaited(teardown());
      socket.send(ClientFrames.unsubscribe(topic));
      completer.complete(List.unmodifiable(collected));
    }
  });

  timer = Timer(timeout, () {
    if (completer.isCompleted) return;
    unawaited(teardown());
    completer.completeError(
      TimeoutException(
        'subscribeAndCollect: only ${collected.length}/$count frames for '
        '"$topic" arrived within $timeout',
        timeout,
      ),
    );
  });

  socket.send(ClientFrames.subscribe(topic));

  return completer.future;
}

/// Creates a session named [name] (optionally in [dir]) via
/// `BastionApi.createSession`, invokes [body] with that name, and deletes
/// the session in a `finally` — cleanup runs even when [body] throws, and
/// the original error still propagates.
///
/// Only errors thrown by the cleanup `deleteSession` call itself are
/// swallowed (best-effort teardown), so a cleanup failure never masks the
/// real result or the original error from [body].
Future<T> withManagedSession<T>(
  BastionApi api,
  Future<T> Function(String name) body, {
  required String name,
  String? dir,
}) async {
  await api.createSession(name, dir: dir);
  try {
    return await body(name);
  } finally {
    try {
      await api.deleteSession(name);
    } catch (_) {
      // Best-effort cleanup — never let a teardown failure mask the real
      // result or the original error from `body`.
    }
  }
}

/// Listens on [socket]'s shared broadcast [BastionSocket.frames] stream and
/// resolves with the next [count] decoded [EventFrame]s whose `event` field
/// equals [event].
///
/// `event` frames (e.g. `workflow_done`) are broadcast to ALL connected
/// clients with no subscribe-topic gate — [subscribeAndCollect]'s
/// `_matchesTopic` only matches `sessions`/`pane` frames and always returns
/// `false` for `event` frames, so this collector does not send a
/// `subscribe` frame at all; simply being connected is enough to observe
/// the broadcast.
///
/// Registers the listener synchronously before returning the future (mirror
/// [subscribeAndCollect]'s subscribe-before-listen race-avoidance
/// discipline) — callers must call this **before** triggering whatever
/// server-side transition is expected to emit the event, so no frame is
/// lost to a race.
///
/// Throws a [TimeoutException] (tearing down the subscription first) if
/// fewer than [count] matching frames arrive within [timeout].
Future<List<EventFrame>> collectEvents(
  BastionSocket socket, {
  required String event,
  int count = 1,
  Duration timeout = const Duration(seconds: 30),
}) {
  final collected = <EventFrame>[];
  final completer = Completer<List<EventFrame>>();
  late final StreamSubscription<BastionFrame> sub;
  Timer? timer;

  Future<void> teardown() async {
    timer?.cancel();
    await sub.cancel();
  }

  sub = socket.frames.listen((frame) {
    if (completer.isCompleted) return;
    if (frame is! EventFrame) return;
    if (frame.event != event) return;
    collected.add(frame);
    if (collected.length >= count) {
      unawaited(teardown());
      completer.complete(List.unmodifiable(collected));
    }
  });

  timer = Timer(timeout, () {
    if (completer.isCompleted) return;
    unawaited(teardown());
    completer.completeError(
      TimeoutException(
        'collectEvents: only ${collected.length}/$count "$event" frames '
        'arrived within $timeout',
        timeout,
      ),
    );
  });

  return completer.future;
}

/// Writes a minimal valid `sdlc-flow-state.json` fixture file to
/// `<planningDir>/<specSlug>/sdlc/sdlc-flow-state.json`, creating parent
/// directories recursively.
///
/// Matches the shape `bastion` parses in `src/serve/status/flow.rs`'s
/// `FlowState` (and the BU.8.A `kFixtureFlowStateJson` fixture): a JSON
/// object carrying `spec_slug`, `status`, and — when [pr] is given — `pr`,
/// PLUS the other fields `FlowState` requires to deserialize at all
/// (`branch`, `current_task`, `started_at`, `updated_at` — all
/// non-`Option` in the Rust struct, so a file missing any of them fails
/// `serde_json::from_str` and is silently skipped by `collect_flow_states`,
/// never establishing a baseline or emitting a transition event). Those
/// four are given fixed, non-load-bearing placeholder values since only
/// `spec_slug`/`status` (and `pr`) matter to the [FlowWatcher] transition
/// logic. Encodes via `dart:convert`'s [jsonEncode] rather than string
/// interpolation, so the written file is always valid JSON regardless of
/// the field values passed.
Future<void> writeFixtureFlowState(
  String planningDir, {
  required String specSlug,
  required String status,
  String? pr,
}) async {
  final dir = Directory('$planningDir/$specSlug/sdlc');
  await dir.create(recursive: true);
  final payload = <String, dynamic>{
    'spec_slug': specSlug,
    'branch': '$specSlug-flow',
    'status': status,
    'current_task': 1,
    'started_at': '2026-07-19T00:00:00Z',
    'updated_at': '2026-07-19T00:00:00Z',
  };
  if (pr != null) payload['pr'] = pr;
  final file = File('${dir.path}/sdlc-flow-state.json');
  await file.writeAsString(jsonEncode(payload));
}

/// Listens on [socket]'s shared broadcast [BastionSocket.frames] stream and
/// resolves with the next [count] decoded [BastionFrame]s for which [match]
/// returns `true`.
///
/// Unlike [subscribeAndCollect], this sends **no** `subscribe` frame — the
/// caller is responsible for triggering whatever produces the frame (e.g.
/// sending a bad-topic `subscribe` to elicit an `error` frame, or relying on
/// an already-active subscription that resumes after a reconnect). Register it
/// **before** triggering, mirroring the subscribe-before-listen discipline of
/// [subscribeAndCollect]/[collectEvents], so no frame is lost to a race.
///
/// Throws a [TimeoutException] (tearing down the subscription first) if fewer
/// than [count] matching frames arrive within [timeout].
Future<List<BastionFrame>> collectFrames(
  BastionSocket socket, {
  required bool Function(BastionFrame frame) match,
  int count = 1,
  Duration timeout = const Duration(seconds: 30),
}) {
  final collected = <BastionFrame>[];
  final completer = Completer<List<BastionFrame>>();
  late final StreamSubscription<BastionFrame> sub;
  Timer? timer;

  Future<void> teardown() async {
    timer?.cancel();
    await sub.cancel();
  }

  sub = socket.frames.listen((frame) {
    if (completer.isCompleted) return;
    if (!match(frame)) return;
    collected.add(frame);
    if (collected.length >= count) {
      unawaited(teardown());
      completer.complete(List.unmodifiable(collected));
    }
  });

  timer = Timer(timeout, () {
    if (completer.isCompleted) return;
    unawaited(teardown());
    completer.completeError(
      TimeoutException(
        'collectFrames: only ${collected.length}/$count matching frames '
        'arrived within $timeout',
        timeout,
      ),
    );
  });

  return completer.future;
}

/// Completes when [socket]'s [BastionSocket.statusStream] next reaches
/// [target] — or immediately if [socket.status] already equals [target].
///
/// Because the subscription is registered synchronously when this is called,
/// callers driving an initial connect should create the future **before**
/// calling `socket.connect()` so the `connected` transition can't be missed:
/// ```dart
/// final connected = awaitStatus(socket, ConnectionStatus.connected);
/// socket.connect();
/// await connected;
/// ```
/// Throws a [TimeoutException] if [target] is not reached within [timeout].
Future<void> awaitStatus(
  BastionSocket socket,
  ConnectionStatus target, {
  Duration timeout = const Duration(seconds: 30),
}) {
  if (socket.status == target) return Future<void>.value();
  return socket.statusStream
      .firstWhere((s) => s == target)
      .timeout(timeout)
      .then((_) {});
}
