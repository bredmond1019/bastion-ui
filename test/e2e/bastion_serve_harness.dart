/// Reusable test harness that boots a real `bastion serve` subprocess for
/// service-level e2e tests (see `test/e2e/serve_contract_e2e_test.dart`).
///
/// Responsibilities:
///   - Locate the sibling-repo `bastion` binary (env override `BASTION_BIN`,
///     else `../bastion/target/release/bastion`, else
///     `../bastion/target/debug/bastion`). Returns `null` from [start] when
///     none is found — callers must treat that as a skip, not a failure.
///   - Allocate an ephemeral port (bind `ServerSocket` to port 0, read the
///     assigned port, close it) — never hardcode 4317.
///   - Spawn `bastion serve --addr 127.0.0.1:<port> --token <token>` with an
///     explicit environment map ([bastionServeHarnessChildEnvironment]) that
///     leaves `DATABASE_URL` unset (the server is absent-tolerant and skips
///     mounting the engine surface) but forwards `PATH` and the locale vars
///     `tmux` needs to format its output correctly.
///   - Poll `GET /health` until it returns 200, with a bounded timeout;
///     fail fast if the process exits before becoming ready.
///   - Expose [host]/[port]/[token] for constructing real `BastionApi` /
///     `BastionSocket` clients, and a [stop] teardown that kills the
///     process.
library;

import 'dart:async';
import 'dart:io';

/// The bearer token the harness spawns `bastion serve` with, and that test
/// clients should use for authenticated requests.
const String bastionServeHarnessTestToken = 'e2e-test-token';

/// A deliberately-wrong token for driving the fatal-auth (401) path.
const String bastionServeHarnessWrongToken = 'e2e-wrong-token';

/// Env var that flips the e2e test from silent self-skip to hard failure
/// when no `bastion` binary can be located. Set it (to a truthy value) in
/// CI or any run that must guarantee the service-level e2e actually ran,
/// rather than green-because-skipped.
const String bastionE2eRequireEnvVar = 'BASTION_E2E_REQUIRE';

/// Whether strict mode is enabled: a missing `bastion` binary should be a
/// hard failure rather than a skip. Controlled by [bastionE2eRequireEnvVar];
/// truthy values are `1`, `true`, `yes`, `on` (case- and whitespace-
/// insensitive). Anything else (including unset/empty) leaves the default
/// self-skip behavior in place.
///
/// Pass [environment] to test the parse in isolation; defaults to the real
/// process environment.
bool bastionE2eRequireBinary([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final raw = env[bastionE2eRequireEnvVar]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
}

/// Env var keys forwarded from the parent process into the spawned `bastion
/// serve` child, in addition to `PATH` (which is always forwarded).
///
/// `LANG`/`LC_ALL` matter beyond cosmetics: without a UTF-8 locale, some
/// `tmux` builds (observed on tmux 3.6b/macOS) silently substitute a
/// non-tab byte for the tab field separator in `tmux list-sessions`'s
/// custom-format output, which makes every line fail bastion's
/// `parse_sessions`/`min 3 tab-separated fields` check and drops it —
/// `GET /api/sessions` then always returns `[]`, even for sessions that
/// really exist. Forwarding the parent's locale keeps the child's `tmux`
/// invocations behaving the same way an interactive shell's would.
const List<String> bastionServeHarnessForwardedEnvKeys = ['LANG', 'LC_ALL'];

/// Builds the explicit environment map [BastionServeHarness.start] spawns
/// `bastion serve` with, given the (real or test-double) parent
/// [parentEnvironment] (defaults to [Platform.environment]).
///
/// Deliberately NOT the full inherited environment — `DATABASE_URL` and any
/// engine-api-key vars are always left unset so the server stays DB-free
/// per `bastion/src/serve/mod.rs`'s absent-tolerance. Only `PATH` (required
/// to locate the `tmux` binary at all) and the locale vars in
/// [bastionServeHarnessForwardedEnvKeys] (required for `tmux` to format its
/// `-F` output correctly, see that constant's doc) are forwarded, and only
/// when actually present (and non-empty for the locale vars) in
/// [parentEnvironment].
Map<String, String> bastionServeHarnessChildEnvironment([
  Map<String, String>? parentEnvironment,
]) {
  final parent = parentEnvironment ?? Platform.environment;
  final env = <String, String>{'PATH': parent['PATH'] ?? ''};
  for (final key in bastionServeHarnessForwardedEnvKeys) {
    final value = parent[key];
    if (value != null && value.isNotEmpty) {
      env[key] = value;
    }
  }
  return env;
}

/// A running `bastion serve` subprocess ready to be driven by real clients.
final class BastionServeHarness {
  BastionServeHarness._({
    required this.host,
    required this.port,
    required this.token,
    required this.process,
  });

  /// Host the server is bound to (always `127.0.0.1`).
  final String host;

  /// Ephemeral port the server was allocated at spawn time.
  final int port;

  /// Bearer token the server was started with.
  final String token;

  final Process process;

  /// Locate the `bastion` binary using the documented precedence:
  /// env `BASTION_BIN`, then `../bastion/target/release/bastion`, then
  /// `../bastion/target/debug/bastion`. Returns `null` when none exists.
  static String? locateBinary() {
    final envOverride = Platform.environment['BASTION_BIN'];
    if (envOverride != null && envOverride.isNotEmpty) {
      if (File(envOverride).existsSync()) return envOverride;
      // An explicit override that doesn't exist is still "not found" for
      // skip purposes — callers should not fail loudly for a stale env var.
      return null;
    }
    const candidates = [
      '../bastion/target/release/bastion',
      '../bastion/target/debug/bastion',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Allocate an ephemeral port by binding a [ServerSocket] to port 0,
  /// reading the assigned port, then releasing it immediately. There is a
  /// small bind-then-release race between this call and the subprocess
  /// binding the same port; callers may retry once on spawn failure.
  static Future<int> _allocateEphemeralPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Poll `GET /health` on `http://127.0.0.1:<port>/health` until it
  /// returns 200, or throw a [TimeoutException] after [timeout] elapses.
  /// Fails fast (throws [StateError]) if [process] exits before the server
  /// becomes ready.
  static Future<void> _waitForHealth({
    required int port,
    required Process process,
    required Duration timeout,
  }) async {
    final client = HttpClient();
    final deadline = DateTime.now().add(timeout);
    Object? exitCode;
    final exitFuture = process.exitCode.then((code) => exitCode = code);
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (exitCode != null) {
          throw StateError(
            'bastion serve exited early with code $exitCode before '
            'becoming ready',
          );
        }
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/health'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) {
            return;
          }
        } catch (_) {
          // Server not accepting connections yet — retry until timeout.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw TimeoutException(
        'bastion serve did not become ready within $timeout',
      );
    } finally {
      client.close(force: true);
      // Don't await exitFuture indefinitely — it only matters while polling.
      unawaited(exitFuture.catchError((_) => -1));
    }
  }

  /// Locate the binary, allocate a port, spawn `bastion serve`, and wait
  /// for `/health` to become ready. Returns `null` (a skip sentinel) when
  /// no binary is found — callers must call `markTestSkipped(...)` in that
  /// case rather than treating it as a failure.
  ///
  /// Throws if a binary is found but the server fails to become ready
  /// within [readyTimeout] — that is a real harness failure, not a skip.
  static Future<BastionServeHarness?> start({
    Duration readyTimeout = const Duration(seconds: 15),
  }) async {
    final binaryPath = locateBinary();
    if (binaryPath == null) {
      return null;
    }

    final port = await _allocateEphemeralPort();
    final process = await Process.start(
      binaryPath,
      [
        'serve',
        '--addr',
        '127.0.0.1:$port',
        '--token',
        bastionServeHarnessTestToken,
      ],
      environment: bastionServeHarnessChildEnvironment(),
      includeParentEnvironment: false,
    );

    try {
      await _waitForHealth(port: port, process: process, timeout: readyTimeout);
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }

    return BastionServeHarness._(
      host: '127.0.0.1',
      port: port,
      token: bastionServeHarnessTestToken,
      process: process,
    );
  }

  /// Kill the spawned `bastion serve` process. Safe to call more than once.
  Future<void> stop() async {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort — the sigkill was already sent.
    }
  }
}
