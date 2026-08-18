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
///   - **Opt-in fixture-workspace seam** ([start]'s `workspaceFixture`
///     param, default `false`): when requested, provisions a temp
///     `XDG_CONFIG_HOME` root via `provisionWorkspaceFixture()` (see
///     `test/e2e/fixtures/workspace_fixture.dart`) — a `[workspaces]`
///     `config.toml` registry plus fixture repo trees — and merges
///     `XDG_CONFIG_HOME=<tmp>` into the spawn env so the child `bastion
///     serve` reads that registry instead of the user's real
///     `~/.config/bastion/config.toml`. The no-fixture spawn env is
///     unaffected (Phase 7 tests, which call `start()` with no fixture,
///     stay byte-for-byte unchanged). [fixtureRepos] exposes the
///     provisioned repo names to callers; the temp dir is removed
///     (best-effort) in [stop]. [fixtureWorkspaceRoot] exposes the
///     provisioned temp dir itself (`null` when no fixture was requested),
///     and [fixtureRepoPlanningDir] resolves a fixture repo's `planning/`
///     path within it — both let callers (e.g. the BU.8.B workflow_done
///     transition test) write additional flow-state fixtures at runtime.
library;

import 'dart:async';
import 'dart:io';

import 'fixtures/workspace_fixture.dart';

/// The bearer token the harness spawns `bastion serve` with, and that test
/// clients should use for authenticated requests.
const String bastionServeHarnessTestToken = 'e2e-test-token';

/// A deliberately-wrong token for driving the fatal-auth (401) path.
const String bastionServeHarnessWrongToken = 'e2e-wrong-token';

/// Default budget for a spawned `bastion serve` child process to answer
/// `GET /health` with 200 before the harness gives up and reports a boot
/// failure. 15s was picked as generous headroom over the process's typical
/// warm-start cost (binary load + port bind + route registration) on a
/// shared dev machine, while still failing a genuinely-stuck spawn (bad
/// binary, port contention, a hung dependency) inside a single test's
/// patience rather than the suite's. Like [e2e_support.dart]'s
/// `kDefaultCollectorTimeout`, this value deliberately does not try to
/// distinguish "slow but correct" from "actually hung" — it is one shared
/// default, not a diagnostic. Call sites that know a given boot is
/// legitimately slower (e.g. under load, or with a larger fixture
/// workspace) should pass their own `readyTimeout:` override rather than
/// widening this default.
const Duration kDefaultServeReadyTimeout = Duration(seconds: 15);

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

/// Env var keys that, together, let the spawned `bastion serve` child mount
/// the Section 18 engine routes (§18.1: both must be set or neither
/// mounts). Forwarded from the parent environment ONLY when
/// [bastionServeHarnessChildEnvironment]'s `forwardEngineEnv` (or
/// [BastionServeHarness.start]'s `engineMount`) is explicitly `true` — never
/// by default, and never with a hardcoded/fixture value. See that
/// function's doc for why the default must stay DB-free.
const List<String> bastionServeHarnessEngineEnvKeys = [
  'DATABASE_URL',
  'BASTION_ENGINE_API_KEY',
];

/// Builds the explicit environment map [BastionServeHarness.start] spawns
/// `bastion serve` with, given the (real or test-double) parent
/// [parentEnvironment] (defaults to [Platform.environment]).
///
/// Deliberately NOT the full inherited environment — `DATABASE_URL` and any
/// engine-api-key vars are left unset by default so the server stays
/// DB-free per `bastion/src/serve/mod.rs`'s absent-tolerance. Only `PATH`
/// (required to locate the `tmux` binary at all) and the locale vars in
/// [bastionServeHarnessForwardedEnvKeys] (required for `tmux` to format its
/// `-F` output correctly, see that constant's doc) are forwarded, and only
/// when actually present (and non-empty for the locale vars) in
/// [parentEnvironment].
///
/// Pass [forwardEngineEnv]: `true` to opt into forwarding
/// [bastionServeHarnessEngineEnvKeys] (`DATABASE_URL` +
/// `BASTION_ENGINE_API_KEY`) from [parentEnvironment] when present and
/// non-empty there — this is the ONLY way those vars ever reach the child;
/// the value always comes from the parent process environment, never a
/// literal or fixture default. **The default (`false`) is unchanged from
/// before this parameter existed** — every existing call site and the
/// pinned 'never forwards' test keep passing untouched.
Map<String, String> bastionServeHarnessChildEnvironment([
  Map<String, String>? parentEnvironment,
  bool forwardEngineEnv = false,
]) {
  final parent = parentEnvironment ?? Platform.environment;
  final env = <String, String>{'PATH': parent['PATH'] ?? ''};
  for (final key in bastionServeHarnessForwardedEnvKeys) {
    final value = parent[key];
    if (value != null && value.isNotEmpty) {
      env[key] = value;
    }
  }
  if (forwardEngineEnv) {
    for (final key in bastionServeHarnessEngineEnvKeys) {
      final value = parent[key];
      if (value != null && value.isNotEmpty) {
        env[key] = value;
      }
    }
  }
  return env;
}

/// Reports whether an engine-mounted `bastion serve` is obtainable in the
/// current environment: both [bastionServeHarnessEngineEnvKeys] are present
/// and non-empty in [parentEnvironment] (defaults to [Platform.environment])
/// AND a `bastion` binary can be located ([BastionServeHarness.locateBinary]).
///
/// Engine e2e tests should call this to self-skip cleanly — the same way
/// every other e2e test in this suite self-skips when
/// [BastionServeHarness.locateBinary] returns `null` — rather than failing
/// when the operator hasn't exported an engine API key locally or in CI.
bool bastionServeHarnessEngineMountAvailable([
  Map<String, String>? parentEnvironment,
]) {
  final parent = parentEnvironment ?? Platform.environment;
  final hasEngineEnv = bastionServeHarnessEngineEnvKeys.every((key) {
    final value = parent[key];
    return value != null && value.isNotEmpty;
  });
  if (!hasEngineEnv) return false;
  return BastionServeHarness.locateBinary() != null;
}

/// A running `bastion serve` subprocess ready to be driven by real clients.
final class BastionServeHarness {
  BastionServeHarness._({
    required this.host,
    required this.port,
    required this.token,
    required Process process,
    required String binaryPath,
    required Map<String, String> environment,
    Directory? fixtureDir,
  }) : _process = process, // ignore: prefer_initializing_formals
       _binaryPath = binaryPath, // ignore: prefer_initializing_formals
       _environment = environment, // ignore: prefer_initializing_formals
       _fixtureDir = fixtureDir; // ignore: prefer_initializing_formals

  /// Host the server is bound to (always `127.0.0.1`).
  final String host;

  /// Ephemeral port the server was allocated at spawn time.
  final int port;

  /// Bearer token the server was started with.
  final String token;

  /// The running `bastion serve` subprocess. Reassigned by [restart]; read it
  /// through the [process] getter rather than capturing this field directly.
  Process _process;

  /// The current `bastion serve` subprocess.
  Process get process => _process;

  /// The binary path and spawn environment captured at [start] so [restart]
  /// can respawn a byte-for-byte-identical server on the same port (including
  /// any fixture `XDG_CONFIG_HOME`).
  final String _binaryPath;
  final Map<String, String> _environment;

  /// The provisioned fixture-workspace temp dir, if [start] was called with
  /// `workspaceFixture: true`; `null` otherwise. Removed (best-effort) by
  /// [stop].
  final Directory? _fixtureDir;

  /// Names of the fixture repos provisioned in the workspace registry, if
  /// [start] was called with `workspaceFixture: true`; empty otherwise. Lets
  /// callers avoid hardcoding the fixture repo names.
  List<String> get fixtureRepos =>
      _fixtureDir == null ? const [] : kFixtureRepoNames;

  /// The provisioned fixture-workspace temp dir, if [start] was called with
  /// `workspaceFixture: true`; `null` otherwise. Read-only access to what
  /// [_fixtureDir] already tracks internally — lets callers write extra
  /// fixture content (e.g. additional `sdlc-flow-state.json` files) into
  /// the same temp root the spawned server reads from.
  Directory? get fixtureWorkspaceRoot => _fixtureDir;

  /// Resolves the `planning/` directory for fixture repo [repo] within the
  /// provisioned fixture-workspace root (the BU.8.A layout:
  /// `<root>/repos/<repo>/planning`).
  ///
  /// Throws a [StateError] if [start] was not called with
  /// `workspaceFixture: true` (i.e. [fixtureWorkspaceRoot] is `null`) —
  /// misuse should fail loudly rather than silently resolve a bogus path.
  String fixtureRepoPlanningDir(String repo) {
    final root = _fixtureDir;
    if (root == null) {
      throw StateError(
        'fixtureRepoPlanningDir() called but the harness was not started '
        'with workspaceFixture: true — there is no fixture workspace root '
        'to resolve against.',
      );
    }
    return '${root.path}/repos/$repo/planning';
  }

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
  ///
  /// When [workspaceFixture] is `true` (default `false`), provisions a temp
  /// fixture workspace via `provisionWorkspaceFixture()` and spawns the
  /// child with `XDG_CONFIG_HOME` pointed at it, so the server reads the
  /// fixture `[workspaces]` registry instead of the user's real
  /// `~/.config/bastion/config.toml`. When `false` (the default), the spawn
  /// env is unchanged from before this seam existed.
  ///
  /// When [engineMount] is `true` (default `false`), forwards
  /// `DATABASE_URL` + `BASTION_ENGINE_API_KEY` from the parent process
  /// environment (see [bastionServeHarnessChildEnvironment]'s
  /// `forwardEngineEnv`), so the spawned server mounts the Section 18
  /// engine routes per §18.1. Prefer
  /// [bastionServeHarnessEngineMountAvailable] to self-skip a test cleanly
  /// when the parent environment or binary makes this unobtainable, rather
  /// than passing `engineMount: true` and letting `/health` time out.
  static Future<BastionServeHarness?> start({
    Duration readyTimeout = kDefaultServeReadyTimeout,
    bool workspaceFixture = false,
    bool engineMount = false,
  }) async {
    final binaryPath = locateBinary();
    if (binaryPath == null) {
      return null;
    }

    Directory? fixtureDir;
    final env = bastionServeHarnessChildEnvironment(null, engineMount);
    if (workspaceFixture) {
      fixtureDir = await provisionWorkspaceFixture();
      env['XDG_CONFIG_HOME'] = fixtureDir.path;
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
      environment: env,
      includeParentEnvironment: false,
    );

    try {
      await _waitForHealth(port: port, process: process, timeout: readyTimeout);
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      if (fixtureDir != null) {
        try {
          await fixtureDir.delete(recursive: true);
        } catch (_) {
          // Best-effort cleanup — don't mask the original failure.
        }
      }
      rethrow;
    }

    return BastionServeHarness._(
      host: '127.0.0.1',
      port: port,
      token: bastionServeHarnessTestToken,
      process: process,
      binaryPath: binaryPath,
      environment: env,
      fixtureDir: fixtureDir,
    );
  }

  /// Kill the spawned `bastion serve` process, then best-effort remove the
  /// provisioned fixture-workspace temp dir (if any). Safe to call more
  /// than once.
  Future<void> stop() async {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort — the sigkill was already sent.
    }
    try {
      await _fixtureDir?.delete(recursive: true);
    } catch (_) {
      // Best-effort — a delete error must never mask teardown.
    }
  }

  /// Force a real connection drop by killing the current `bastion serve`
  /// process and respawning an identical one on the **same** `host:port` with
  /// the same environment (including any fixture `XDG_CONFIG_HOME`), then
  /// waiting for `/health`. The server exposes no in-band drop signal, so this
  /// is how the reconnect e2e (BU.9.D) exercises the client's
  /// backoff-reconnect + resubscribe-replay path against a real server.
  ///
  /// The fixture temp dir (if any) is deliberately NOT re-provisioned — the
  /// same `XDG_CONFIG_HOME` is reused, so any flow-state or registry content
  /// written during the test survives the restart.
  ///
  /// Retries the respawn up to [maxAttempts] times to absorb the brief window
  /// where the just-freed port is not yet re-bindable (e.g. lingering
  /// TIME_WAIT); throws a [StateError] only if every attempt fails to become
  /// ready within [readyTimeout].
  Future<void> restart({
    Duration readyTimeout = kDefaultServeReadyTimeout,
    int maxAttempts = 5,
  }) async {
    _process.kill(ProcessSignal.sigkill);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort — the sigkill was already sent.
    }

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final process = await Process.start(
        _binaryPath,
        ['serve', '--addr', '127.0.0.1:$port', '--token', token],
        environment: _environment,
        includeParentEnvironment: false,
      );
      try {
        await _waitForHealth(
          port: port,
          process: process,
          timeout: readyTimeout,
        );
        _process = process;
        return;
      } catch (e) {
        lastError = e;
        process.kill(ProcessSignal.sigkill);
        // Brief pause before rebinding the same port — handles the transient
        // window where the OS has not yet released it after the prior process.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw StateError(
      'bastion serve failed to restart on port $port after $maxAttempts '
      'attempts (last error: $lastError)',
    );
  }
}
