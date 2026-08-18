/// HTTP client for the embedded engine mount — `bastion serve`'s
/// `engine-serve` route table (serve-api.md §18, v0.5, `BA.7.C`).
///
/// This is a SEPARATE client from [BastionApi] on purpose:
///   - The engine mount lives at the **server root** with **no `/api`
///     prefix** (`http://$host:$port/workflows`, never `.../api/workflows`).
///   - Auth is an `X-API-Key` header, never `Authorization: Bearer` — the
///     two schemes are independent and neither is layered on the other's
///     routes (serve-api §18.2).
///   - The engine only mounts when the SERVER has both `DATABASE_URL` and
///     `BASTION_ENGINE_API_KEY` set (§18.1); absent either, every engine
///     route is unmounted and this client must degrade to a typed
///     unavailability state, never crash or misreport the cause.
///
/// Reuses [HttpTransport]/[IoHttpTransport] and the [FatalAuthError]/
/// [ApiError] error types from `bastion_api.dart` rather than forking a
/// parallel transport or error hierarchy — the only NEW type here is
/// [EngineNotConfiguredError], which has no existing analog because it
/// fires before any request is made.
///
/// Rule 7 (non-negotiable): the API key is never put into an exception
/// message, a `toString()`, or a log line anywhere in this file. Errors
/// surfaced from this client carry only the server's status code and body.
library;

import 'dart:convert';
import 'dart:io';

import 'bastion_api.dart'
    show ApiError, FatalAuthError, HttpTransport, IoHttpTransport;
import '../models/dto.dart' show ErrorPayload;

// ---------------------------------------------------------------------------
// Not-configured error
// ---------------------------------------------------------------------------

/// Thrown by every read method when no engine API key is held locally.
///
/// This is a **client-side** short-circuit — no HTTP request is issued.
/// Carries no key material (there is none to carry: the whole point of this
/// type is that the client has nothing configured).
final class EngineNotConfiguredError implements Exception {
  const EngineNotConfiguredError();

  @override
  String toString() => 'EngineNotConfiguredError(no engine API key configured)';
}

// ---------------------------------------------------------------------------
// Mount probe result
// ---------------------------------------------------------------------------

/// The five distinguishable outcomes of [EngineApi.probeMount].
///
/// Distinguishing [notMounted] from [unauthorized] is the subtle part: an
/// unmounted server has no `/workflows` route at all (404/405), a mounted
/// one answers 401 to a bad key. A boolean "is the engine up" cannot tell
/// an operator "your key is wrong" from "this server was never started
/// with engine env vars" — that is the whole reason this is a five-way
/// enum rather than a bool.
enum EngineStatus {
  /// No key is held locally — [EngineApi] is not configured. No request
  /// was made.
  notConfigured,

  /// The server responded, but the engine routes are absent (the server
  /// booted without `DATABASE_URL`/`BASTION_ENGINE_API_KEY` per §18.1).
  notMounted,

  /// The engine is mounted, but the configured key was rejected (401).
  unauthorized,

  /// The engine is mounted and the key was accepted.
  available,

  /// The probe could not reach the server at all (socket-level failure).
  unreachable,
}

// ---------------------------------------------------------------------------
// Control outcomes (serve-api.md §18, v0.30 — pause/resume/abort)
// ---------------------------------------------------------------------------
//
// `401` is deliberately NOT a member of any of these sealed hierarchies: it
// is thrown as [FatalAuthError] by [EngineApi._checkStatus], exactly as
// every other route on this client already handles it — a rejected key is
// not a per-route outcome, it is a client-wide fatal condition the caller
// must stop retrying on. Every OTHER documented status code is modelled as
// a distinct outcome rather than collapsed into a single success/failure
// bool: pause/resume/abort's whole reason for existing on a phone is that
// the operator's next action differs by code (already-suspended is not the
// same problem as unknown-run).
//
// The 202 outcome for each route is named for the in-flight VERB
// (`pausing`/`resuming`/`aborting`), never an achieved state — the engine
// has only ACCEPTED the request; the run transitions later, and the next
// read (not this response) is the source of truth for whether it landed.

/// Outcome of [EngineApi.pauseRun].
sealed class PauseOutcome {
  const PauseOutcome();
}

/// `202 {run_id, status:'pausing'}` — the pause request was accepted. The
/// run is NOT yet paused/suspended; that is a later read's job to report.
final class PausePausing extends PauseOutcome {
  final String runId;
  final String status;
  const PausePausing({required this.runId, required this.status});
}

/// `409 {run_id, status:'suspended', error:'run is already suspended'}`.
final class PauseAlreadySuspended extends PauseOutcome {
  final String runId;
  final String error;
  const PauseAlreadySuspended({required this.runId, required this.error});
}

/// `404 {error:'unknown or finished run'}`.
final class PauseNotFound extends PauseOutcome {
  final String error;
  const PauseNotFound(this.error);
}

/// Outcome of [EngineApi.resumeRun].
sealed class ResumeOutcome {
  const ResumeOutcome();
}

/// `202 {run_id, event_id, status:'resuming', resume_at}` — accepted, not
/// yet resumed.
final class ResumeResuming extends ResumeOutcome {
  final String runId;
  final String eventId;
  final String status;
  final String? resumeAt;
  const ResumeResuming({
    required this.runId,
    required this.eventId,
    required this.status,
    this.resumeAt,
  });
}

/// `409 {error:'resume already in flight'}`.
final class ResumeAlreadyResuming extends ResumeOutcome {
  final String error;
  const ResumeAlreadyResuming(this.error);
}

/// `404 {error:'unknown or non-resumable run'}`.
final class ResumeNotFound extends ResumeOutcome {
  final String error;
  const ResumeNotFound(this.error);
}

/// `422 {error:'policy resolution failed', message}` — the server's
/// [message] names the unknown `workflow_type` and is the only useful
/// diagnostic available here; it MUST be carried through to the caller
/// verbatim, never dropped in favour of the generic `error` string.
final class ResumePolicyFailed extends ResumeOutcome {
  final String error;
  final String? message;
  const ResumePolicyFailed({required this.error, this.message});
}

/// Outcome of [EngineApi.abortRun].
sealed class AbortOutcome {
  const AbortOutcome();
}

/// `202 {run_id, status:'aborting'}` — accepted, not yet aborted.
final class AbortAborting extends AbortOutcome {
  final String runId;
  final String status;
  const AbortAborting({required this.runId, required this.status});
}

/// `404 {error:'unknown or finished run'}`.
final class AbortNotFound extends AbortOutcome {
  final String error;
  const AbortNotFound(this.error);
}

/// One row of `GET /events/suspended` — a currently-suspended run.
final class SuspendedRunDto {
  final String runId;
  final String? workflowType;
  final String? createdAt;
  final String? suspendedAt;
  final String? resumeAt;
  final String? reason;

  const SuspendedRunDto({
    required this.runId,
    this.workflowType,
    this.createdAt,
    this.suspendedAt,
    this.resumeAt,
    this.reason,
  });

  factory SuspendedRunDto.fromJson(Map<String, dynamic> json) {
    return SuspendedRunDto(
      runId: json['run_id'] as String,
      workflowType: json['workflow_type'] as String?,
      createdAt: json['created_at'] as String?,
      suspendedAt: json['suspended_at'] as String?,
      resumeAt: json['resume_at'] as String?,
      reason: json['reason'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// EngineApi
// ---------------------------------------------------------------------------

/// Client for the embedded engine mount (serve-api.md §18).
///
/// ```dart
/// final engine = EngineApi(host: '100.64.0.1', port: 4317, key: storedKey);
/// switch (await engine.probeMount()) {
///   case EngineStatus.available:
///     final types = await engine.getWorkflows();
///   // ...
/// }
/// engine.dispose();
/// ```
final class EngineApi {
  /// Server root — deliberately NO `/api` segment (serve-api §18).
  final String _baseUrl;

  /// The configured key, or `null` when not configured. A blank string is
  /// normalized to `null` at construction — an empty `X-API-Key` header is
  /// rejected by the server anyway (§18.2.1), so sending one would only
  /// waste a round trip and report the wrong cause.
  final String? _key;

  final HttpTransport _transport;

  /// Create an [EngineApi] targeting `http://<host>:<port>` (server root).
  ///
  /// [key] is the engine API key, or `null`/empty when not yet configured.
  /// [transport] defaults to [IoHttpTransport]; pass a fake in tests.
  EngineApi({
    required String host,
    required int port,
    required String? key,
    HttpTransport? transport,
  }) : _baseUrl = 'http://$host:$port',
       _key = (key == null || key.isEmpty) ? null : key,
       _transport = transport ?? IoHttpTransport();

  /// Whether a (non-empty) key is held locally.
  bool get isConfigured => _key != null;

  Map<String, String> get _headers => {
    'X-API-Key': _key!,
    'Accept': 'application/json',
  };

  /// Throws [EngineNotConfiguredError] without issuing any request when no
  /// key is held locally.
  void _requireConfigured() {
    if (_key == null) {
      throw const EngineNotConfiguredError();
    }
  }

  /// Throw the appropriate typed error for a non-2xx status code; no-op for
  /// 2xx. Mirrors [BastionApi]'s `_checkStatus`, reusing the same error
  /// types — a 401 here means "wrong/rejected key", exactly as it means
  /// "wrong/rejected bearer token" on the console surface.
  void _checkStatus(int statusCode, String body) {
    if (statusCode == 401) {
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw FatalAuthError(const ErrorPayload(code: 'unauthorized'));
      }
      throw FatalAuthError(ErrorPayload.fromJson(json));
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiError(statusCode: statusCode, body: body);
    }
  }

  // -------------------------------------------------------------------------
  // Routes (serve-api.md §18.2)
  // -------------------------------------------------------------------------

  /// `GET /workflows` — the registered workflow-type registry, sorted.
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, [ApiError] on other HTTP
  /// errors, or a [SocketException]/[HttpException] on network failure.
  Future<List<String>> getWorkflows() async {
    _requireConfigured();
    final result = await _transport.get(
      '$_baseUrl/workflows',
      headers: _headers,
    );
    _checkStatus(result.statusCode, result.body);
    final Object? decoded;
    try {
      decoded = jsonDecode(result.body);
    } catch (e) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'invalid JSON: ${result.body}',
      );
    }
    if (decoded is! List) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'expected JSON array: ${result.body}',
      );
    }
    final types = decoded.whereType<String>().toList()..sort();
    return types;
  }

  /// `GET /workflows/{type}/graph` — the DAG schema for a registered
  /// workflow [type]; `404` for an unknown type.
  ///
  /// The graph shape is engine-owned and not mirrored as a Dart DTO here
  /// (no client-side model exists for it in this repo) — the raw decoded
  /// JSON object is returned verbatim.
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, [ApiError] on other HTTP
  /// errors (including the `404` unknown-type case), or a
  /// [SocketException]/[HttpException] on network failure.
  Future<Map<String, dynamic>> getWorkflowGraph(String type) async {
    _requireConfigured();
    final encodedType = Uri.encodeComponent(type);
    final result = await _transport.get(
      '$_baseUrl/workflows/$encodedType/graph',
      headers: _headers,
    );
    _checkStatus(result.statusCode, result.body);
    try {
      return jsonDecode(result.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'invalid JSON: ${result.body}',
      );
    }
  }

  /// `GET /events/{id}` — the raw event payload for run [runId].
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, [ApiError] on other HTTP
  /// errors, or a [SocketException]/[HttpException] on network failure.
  Future<Map<String, dynamic>> getEvent(String runId) async {
    _requireConfigured();
    final encodedRunId = Uri.encodeComponent(runId);
    final result = await _transport.get(
      '$_baseUrl/events/$encodedRunId',
      headers: _headers,
    );
    _checkStatus(result.statusCode, result.body);
    try {
      return jsonDecode(result.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'invalid JSON: ${result.body}',
      );
    }
  }

  /// Decode [body] as a JSON object, or `{}` when it is not valid/is not an
  /// object. Used only by the control routes below, whose non-2xx bodies
  /// this client must read fields out of (`error`, `message`, ...) rather
  /// than throw on — decode failure degrades to an empty map so a missing
  /// field just reads as `null`, never a thrown/obscure decode error.
  Map<String, dynamic> _decodeObjectOrEmpty(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // fall through
    }
    return const {};
  }

  // -------------------------------------------------------------------------
  // Run controls (serve-api.md §18, v0.30 — engine routes, X-API-Key,
  // server root; NOT documented in §18.2's route table for `pause`, which
  // omits it despite engine-serve registering it — see planning/BU.12.D
  // Notes. This client follows the live engine mount, not the doc gap.)
  // -------------------------------------------------------------------------

  /// `POST /events/{run_id}/pause`.
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, or a
  /// [SocketException]/[HttpException] on network failure. Every other
  /// documented status maps to a [PauseOutcome] member rather than being
  /// thrown — see the [PauseOutcome] hierarchy doc comment.
  Future<PauseOutcome> pauseRun(String runId) async {
    _requireConfigured();
    final encodedRunId = Uri.encodeComponent(runId);
    final result = await _transport.post(
      '$_baseUrl/events/$encodedRunId/pause',
      headers: _headers,
    );
    if (result.statusCode == 401) {
      _checkStatus(result.statusCode, result.body);
    }
    final json = _decodeObjectOrEmpty(result.body);
    switch (result.statusCode) {
      case 202:
        return PausePausing(
          runId: (json['run_id'] as String?) ?? runId,
          status: (json['status'] as String?) ?? 'pausing',
        );
      case 409:
        return PauseAlreadySuspended(
          runId: (json['run_id'] as String?) ?? runId,
          error: (json['error'] as String?) ?? 'run is already suspended',
        );
      case 404:
        return PauseNotFound(
          (json['error'] as String?) ?? 'unknown or finished run',
        );
      default:
        throw ApiError(statusCode: result.statusCode, body: result.body);
    }
  }

  /// `POST /events/{event_id}/resume`.
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, or a
  /// [SocketException]/[HttpException] on network failure. Every other
  /// documented status maps to a [ResumeOutcome] member rather than being
  /// thrown — see the [ResumeOutcome] hierarchy doc comment. Note the
  /// route path segment is `event_id`, not `run_id` (serve-api §18).
  Future<ResumeOutcome> resumeRun(String eventId) async {
    _requireConfigured();
    final encodedEventId = Uri.encodeComponent(eventId);
    final result = await _transport.post(
      '$_baseUrl/events/$encodedEventId/resume',
      headers: _headers,
    );
    if (result.statusCode == 401) {
      _checkStatus(result.statusCode, result.body);
    }
    final json = _decodeObjectOrEmpty(result.body);
    switch (result.statusCode) {
      case 202:
        return ResumeResuming(
          runId: (json['run_id'] as String?) ?? eventId,
          eventId: (json['event_id'] as String?) ?? eventId,
          status: (json['status'] as String?) ?? 'resuming',
          resumeAt: json['resume_at'] as String?,
        );
      case 409:
        return ResumeAlreadyResuming(
          (json['error'] as String?) ?? 'resume already in flight',
        );
      case 404:
        return ResumeNotFound(
          (json['error'] as String?) ?? 'unknown or non-resumable run',
        );
      case 422:
        return ResumePolicyFailed(
          error: (json['error'] as String?) ?? 'policy resolution failed',
          message: json['message'] as String?,
        );
      default:
        throw ApiError(statusCode: result.statusCode, body: result.body);
    }
  }

  /// `POST /events/{run_id}/abort`.
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, or a
  /// [SocketException]/[HttpException] on network failure. Every other
  /// documented status maps to an [AbortOutcome] member rather than being
  /// thrown — see the [AbortOutcome] hierarchy doc comment.
  Future<AbortOutcome> abortRun(String runId) async {
    _requireConfigured();
    final encodedRunId = Uri.encodeComponent(runId);
    final result = await _transport.post(
      '$_baseUrl/events/$encodedRunId/abort',
      headers: _headers,
    );
    if (result.statusCode == 401) {
      _checkStatus(result.statusCode, result.body);
    }
    final json = _decodeObjectOrEmpty(result.body);
    switch (result.statusCode) {
      case 202:
        return AbortAborting(
          runId: (json['run_id'] as String?) ?? runId,
          status: (json['status'] as String?) ?? 'aborting',
        );
      case 404:
        return AbortNotFound(
          (json['error'] as String?) ?? 'unknown or finished run',
        );
      default:
        throw ApiError(statusCode: result.statusCode, body: result.body);
    }
  }

  /// `GET /events/suspended` — currently-suspended runs, newest first (as
  /// returned by the server; this client does not re-sort).
  ///
  /// Throws [EngineNotConfiguredError] with no request issued when no key
  /// is configured, [FatalAuthError] on `401`, [ApiError] on other HTTP
  /// errors, or a [SocketException]/[HttpException] on network failure.
  Future<List<SuspendedRunDto>> listSuspended() async {
    _requireConfigured();
    final result = await _transport.get(
      '$_baseUrl/events/suspended',
      headers: _headers,
    );
    _checkStatus(result.statusCode, result.body);
    final Object? decoded;
    try {
      decoded = jsonDecode(result.body);
    } catch (e) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'invalid JSON: ${result.body}',
      );
    }
    if (decoded is! List) {
      throw ApiError(
        statusCode: result.statusCode,
        body: 'expected JSON array: ${result.body}',
      );
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SuspendedRunDto.fromJson)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Mount probe
  // -------------------------------------------------------------------------

  /// Probes `GET /workflows` and maps the outcome to one of the five
  /// [EngineStatus] values. Never throws — every failure mode (missing
  /// key, HTTP error, network failure) is captured in the returned status.
  Future<EngineStatus> probeMount() async {
    if (_key == null) {
      return EngineStatus.notConfigured;
    }
    try {
      final result = await _transport.get(
        '$_baseUrl/workflows',
        headers: _headers,
      );
      if (result.statusCode == 401) {
        return EngineStatus.unauthorized;
      }
      if (result.statusCode == 404 || result.statusCode == 405) {
        return EngineStatus.notMounted;
      }
      if (result.statusCode >= 200 && result.statusCode < 300) {
        return EngineStatus.available;
      }
      // Any other status is treated as unreachable-equivalent: the probe
      // cannot make a positive claim about mount state from it.
      return EngineStatus.unreachable;
    } on SocketException {
      return EngineStatus.unreachable;
    } on HttpException {
      return EngineStatus.unreachable;
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Release resources held by the underlying HTTP transport.
  ///
  /// Only has an effect when using the default [IoHttpTransport].
  void dispose() {
    final t = _transport;
    if (t is IoHttpTransport) {
      t.close();
    }
  }
}
