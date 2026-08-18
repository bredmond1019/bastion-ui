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
