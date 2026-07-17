/// Shared test seam for the e2e coverage tests (BU.7.B/C, BU.8.B).
///
/// This is a plain library (not tagged `e2e`) so it can be imported by both
/// the gating unit tests in `e2e_support_test.dart` and the non-gating
/// `@Tags(['e2e'])` coverage tests that drive a real `bastion serve`. It
/// exports:
///   - [tmuxAvailable] — a self-skip guard for tests that need a real tmux
///     binary on PATH.
///   - `withManagedSession` (added in a later task) — create-yield-cleanup
///     around `BastionApi.createSession`/`deleteSession`.
///   - `subscribeAndCollect` (added in a later task) — subscribe-and-collect
///     N decoded `BastionFrame`s from a `BastionSocket`.
library;

import 'dart:io';

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
