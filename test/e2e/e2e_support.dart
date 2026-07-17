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
library;

import 'dart:async';
import 'dart:io';

import 'package:bastion_ui/models/frame.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/services/bastion_socket.dart';
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
