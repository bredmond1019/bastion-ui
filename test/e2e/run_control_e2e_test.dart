/// Service-level e2e test: boots a REAL `bastion serve` subprocess with the
/// Section 18 engine mount enabled (via [BastionServeHarness.start]'s
/// `engineMount: true`), and drives the real, non-mocked [EngineApi]
/// pause/resume/abort routes against it — no fakes, no mocks.
///
/// Launching a run is BU.12.E's job, not this block's (see
/// `planning/BU.12.D/tasks.md`'s Out of Scope), so [EngineApi] carries no
/// "start a run" method for this test to call. Instead this file triggers a
/// run the same way `engine-serve`'s own Rust integration suite does
/// (`crates/engine-serve/tests/suspend_resume_http.rs`): a raw `POST
/// /events/` against whatever workflow type the live server has registered
/// (discovered via `EngineApi.getWorkflows()`, never hardcoded), with an
/// empty event payload.
///
/// **What this file actually proves (measured 2026-08-18 against the live
/// engine on :4317).** Every registered workflow type in this environment
/// runs to completion in milliseconds — `APPROVE_AND_RUN` went
/// `created_at` .929050 -> `succeeded` .930713, ~1.7ms later — so there is
/// no window in which any dispatchable run can be paused. `LEAD_INGEST`
/// and `HARVEST_APPROVE` behave identically. The only registered type that
/// would stay alive long enough to pause is `SDLC_FLOW`, and triggering
/// that spawns real agent work on the operator's machine, which is out of
/// bounds for a test. So `PausePausing` / `ResumeResuming` are NOT
/// e2e-reachable in this environment (decision D-7, amended into
/// `planning/BU.12.D/tasks.md` after an earlier version of this test
/// asserted `PausePausing` against a run that had already succeeded and
/// failed — the server was correct, the test's premise was not).
///
/// What IS reachable and asserted for real, against a real server:
///   - abort against a known-absent run id -> `AbortNotFound`, no throw;
///   - pause against a run that has genuinely already completed ->
///     `PauseNotFound` — this is a REAL round trip that pins the 404
///     mapping, obtained by triggering a real run and letting it finish;
///   - resume against that same finished (non-resumable) run ->
///     `ResumeNotFound`;
///   - `listSuspended()` parses a real `GET /events/suspended` response —
///     empty is a valid, non-throwing result in this environment.
///
/// The pausing/resuming outcomes are visibly `markTestSkipped` with the
/// measured reason above rather than asserted against a run that cannot be
/// paused, and rather than faking a long-running run to manufacture a
/// pausable window.
///
/// A registered workflow can still legitimately fail to dispatch in this
/// environment (e.g. `SDLC_FLOW`'s policy resolution reads `harness.json`
/// off the spawned server's working directory — an environment property,
/// not a contract property). That failure self-skips with a clear
/// diagnostic, exactly like `workflow_events_e2e_test.dart`'s 504/C007
/// spawn-readiness skip — never a silent pass, never a hard failure for an
/// environment gap this test does not own.
///
/// Tagged `e2e` — excluded from the gating suite (`flutter test
/// --exclude-tags e2e`); run explicitly via `flutter test --tags e2e`.
///
/// The engine API key is read from the real process environment only —
/// never hardcoded, never logged, never interpolated into any string in
/// this file.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/engine_api.dart';

import 'bastion_serve_harness.dart';

/// A syntactically-valid but real UUID no run will ever be minted with —
/// drives the abort-against-an-absent-run assertion without needing a
/// UUID-generating dependency in this repo.
const _absentRunId = '00000000-0000-0000-0000-000000000000';

/// Result of a raw `POST /events/` trigger — mirrors the shape
/// `engine-serve`'s own `trigger_and_wait_suspended!` macro asserts against
/// (`crates/engine-serve/tests/suspend_resume_http.rs`), but over real HTTP
/// rather than an in-process actix service.
final class _TriggerResult {
  final int statusCode;
  final Map<String, dynamic> body;
  const _TriggerResult(this.statusCode, this.body);
}

/// `POST $baseUrl/events/` with `{workflow_type, data: {}}` and the engine
/// key. Not a method on [EngineApi] — launching a run is out of this
/// block's scope (BU.12.E), so this is test-only scaffolding to obtain a
/// real run for the pause/resume assertions below.
Future<_TriggerResult> _triggerRun({
  required String baseUrl,
  required String workflowType,
  required String engineKey,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$baseUrl/events/'));
    request.headers.set('X-API-Key', engineKey);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode({'workflow_type': workflowType, 'data': {}}));
    final response = await request.close();
    final rawBody = await response.transform(utf8.decoder).join();
    Map<String, dynamic> decoded = const {};
    try {
      final parsed = jsonDecode(rawBody);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {
      // Non-JSON body — surface the empty map; the status code alone is
      // enough for this helper's callers to decide skip vs. proceed.
    }
    return _TriggerResult(response.statusCode, decoded);
  } finally {
    client.close(force: true);
  }
}

/// Reason string shown by the two `markTestSkipped` calls for the
/// not-e2e-reachable pausing/resuming outcomes — kept as one constant so
/// both skip sites (and this file's own doc comment) stay in sync.
const _pausingResumingUnreachableReason =
    'PausePausing/ResumeResuming are not e2e-reachable in this '
    'environment: every registered workflow type completes in ~2ms '
    '(measured 2026-08-18, APPROVE_AND_RUN created .929050 -> succeeded '
    '.930713), so no dispatchable run stays alive long enough to pause. '
    'The only long-running type, SDLC_FLOW, would spawn real agent work '
    'and is out of bounds for a test. See planning/BU.12.D/tasks.md '
    'decision D-7.';

void main() {
  group('run control e2e', () {
    BastionServeHarness? harness;

    tearDown(() async {
      // Ensure no bastion serve subprocess is left running even if an
      // assertion above threw.
      await harness?.stop();
      harness = null;
    });

    test('pause/resume/abort/listSuspended map to their real notFound and '
        'empty-list outcomes against a live engine-mounted server; '
        'pausing/resuming are visibly skipped as unreachable', () async {
      if (!bastionServeHarnessEngineMountAvailable()) {
        const whereChecked =
            'checked BASTION_BIN, ../bastion/target/release/bastion, '
            '../bastion/target/debug/bastion, and the parent environment '
            'for DATABASE_URL + BASTION_ENGINE_API_KEY';
        if (bastionE2eRequireBinary()) {
          fail(
            '$bastionE2eRequireEnvVar is set but no engine-mounted '
            'bastion serve could be obtained ($whereChecked) — build a '
            'binary with `cargo build -p bastion` in ../bastion and '
            'export DATABASE_URL + BASTION_ENGINE_API_KEY, or set '
            'BASTION_BIN.',
          );
        }
        markTestSkipped(
          'no engine-mounted bastion serve obtainable ($whereChecked) — '
          'skipping run control e2e test (set '
          '$bastionE2eRequireEnvVar=1 to make this a hard failure '
          'instead)',
        );
        return;
      }

      final engineKey = Platform.environment['BASTION_ENGINE_API_KEY']!;

      harness = await BastionServeHarness.start(engineMount: true);
      final h = harness;
      if (h == null) {
        markTestSkipped(
          'bastion binary became unavailable between the availability '
          'check and start() — skipping run control e2e test',
        );
        return;
      }

      final engine = EngineApi(host: h.host, port: h.port, key: engineKey);
      try {
        // --- abort against a known-absent run: notFound, no throw ----
        final absentAbort = await engine.abortRun(_absentRunId);
        expect(absentAbort, isA<AbortNotFound>());

        // --- listSuspended parses a real response, empty included ----
        final initialSuspended = await engine.listSuspended();
        expect(initialSuspended, isA<List<SuspendedRunDto>>());

        // --- discover a dispatchable workflow type --------------------
        final types = await engine.getWorkflows();
        if (types.isEmpty) {
          markTestSkipped(
            'engine-mounted server has no registered workflow types — '
            'skipping the trigger/pause/resume-on-finished assertions',
          );
          return;
        }
        final workflowType = types.first;

        // --- trigger a real run over raw HTTP --------------------------
        final baseUrl = 'http://${h.host}:${h.port}';
        final trigger = await _triggerRun(
          baseUrl: baseUrl,
          workflowType: workflowType,
          engineKey: engineKey,
        );
        if (trigger.statusCode != 202) {
          // A registered type can still fail to DISPATCH in this
          // environment (e.g. SDLC_FLOW's policy resolution reads
          // harness.json off the server's working directory) — that is
          // an environment property, not a contract property this
          // block owns. Self-skip visibly rather than failing on it.
          markTestSkipped(
            'POST /events/ for workflow_type "$workflowType" returned '
            '${trigger.statusCode} (${trigger.body}) instead of 202 — '
            'no dispatchable run obtainable in this environment, '
            'skipping the pause/resume-on-finished assertions',
          );
          return;
        }
        final runId = trigger.body['run_id'] as String?;
        expect(runId, isNotNull);
        expect(runId, isNotEmpty);

        // --- let the run reach a terminal state. Every registered ------
        // workflow type in this environment finishes in ~2ms, so a
        // short poll is enough; if it is somehow still running after
        // the deadline, this is one of the rare long-lived types and
        // the pause/resume-on-finished assertions below are skipped
        // rather than racing the run.
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        bool reachedTerminal = false;
        while (DateTime.now().isBefore(deadline)) {
          final pauseProbe = await engine.pauseRun(runId!);
          if (pauseProbe is PauseNotFound) {
            reachedTerminal = true;
            break;
          }
          if (pauseProbe is PausePausing) {
            // Genuinely caught the run alive — this is the pausing
            // outcome the earlier failing version of this test assumed
            // was always reachable. Prove it directly if it happens,
            // rather than discarding the signal.
            expect(pauseProbe.runId, runId);
            markTestSkipped(_pausingResumingUnreachableReason);
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        if (!reachedTerminal) {
          markTestSkipped(
            'workflow_type "$workflowType" did not reach a terminal '
            'state within 5s — cannot obtain the pause-on-finished '
            'notFound mapping in this environment for this type',
          );
          return;
        }

        // --- pause against a finished run: real 404 round trip --------
        final pauseOutcome = await engine.pauseRun(runId!);
        expect(pauseOutcome, isA<PauseNotFound>());

        // --- resume against that same non-resumable run: real 404 -----
        final resumeOutcome = await engine.resumeRun(runId);
        expect(resumeOutcome, isA<ResumeNotFound>());

        // --- pausing/resuming are not e2e-reachable here: skip visibly,
        // never asserted against a run that cannot be paused, and never
        // faked.
        markTestSkipped(_pausingResumingUnreachableReason);
      } finally {
        engine.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
