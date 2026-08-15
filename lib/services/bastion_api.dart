/// REST client for `bastion serve` — v0 + session (v0.1) surface.
///
/// Implements:
///   - `GET /health` → [HealthDto]  (public — no bearer required, but harmless to send)
///   - Session REST routes (serve-api.md §10, v0.1): [getSessions], [getPane],
///     [sendKeys], [sendKey], [createSession], [deleteSession].
///
/// A `401` response is decoded as a typed [FatalAuthError] and rethrown;
/// the caller must not retry after receiving [FatalAuthError].
library;

import 'dart:convert';
import 'dart:io';

import '../models/action_dto.dart';
import '../models/attention_dto.dart';
import '../models/board_dto.dart';
import '../models/docs_dto.dart';
import '../models/dto.dart';
import '../models/repo_status_dto.dart';
import '../models/run_dto.dart';
import '../models/session_dto.dart';

// ---------------------------------------------------------------------------
// Transport abstraction (enables unit testing without a real network)
// ---------------------------------------------------------------------------

/// Minimal HTTP interface used by [BastionApi].
///
/// The default implementation uses [dart:io]'s [HttpClient].
/// Tests may supply a [FakeHttpTransport].
abstract interface class HttpTransport {
  /// Perform a GET request and return the response status code + body.
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  });

  /// Perform a POST request with an optional JSON [body] and return the
  /// response status code + body.
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });

  /// Perform a DELETE request and return the response status code + body.
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  });
}

/// Production implementation backed by [dart:io]'s [HttpClient].
final class IoHttpTransport implements HttpTransport {
  final HttpClient _client;

  IoHttpTransport({HttpClient? client}) : _client = client ?? HttpClient();

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (statusCode: response.statusCode, body: body);
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.postUrl(uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    return (statusCode: response.statusCode, body: respBody);
  }

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.deleteUrl(uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    return (statusCode: response.statusCode, body: respBody);
  }

  /// Release underlying socket connections.
  void close({bool force = false}) => _client.close(force: force);
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// Thrown when the server returns a `401 Unauthorized` response.
///
/// This is a **fatal** auth failure — the caller must not retry; it should
/// surface the error to the user and prompt for new credentials.
final class FatalAuthError implements Exception {
  final ErrorPayload payload;

  const FatalAuthError(this.payload);

  @override
  String toString() =>
      'FatalAuthError(code: ${payload.code}, error: ${payload.error})';
}

/// Thrown when a non-auth HTTP error is received (status ≥ 400 and ≠ 401).
final class ApiError implements Exception {
  final int statusCode;
  final String body;

  const ApiError({required this.statusCode, required this.body});

  @override
  String toString() => 'ApiError(statusCode: $statusCode, body: $body)';
}

// ---------------------------------------------------------------------------
// BastionApi
// ---------------------------------------------------------------------------

/// REST client for `bastion serve` v0 HTTP surface.
///
/// ```dart
/// final api = BastionApi(host: '100.64.0.1', port: 4317, token: 'mytoken');
/// final health = await api.getHealth();
/// await api.dispose();
/// ```
final class BastionApi {
  final String _baseUrl;
  final String _token;
  final HttpTransport _transport;

  /// Create a [BastionApi] connected to `http://<host>:<port>`.
  ///
  /// [host] and [port] are resolved at construction time; the base URL is
  /// immutable — create a new instance if the server address changes.
  ///
  /// [transport] defaults to [IoHttpTransport]; pass a fake in tests.
  // Named parameters host/port/token map to private fields; initializing
  // formals cannot be used here because the public parameter names differ
  // from the private field names (e.g. `token` → `_token`).
  // ignore: prefer_initializing_formals
  BastionApi({
    required String host,
    required int port,
    required String token,
    HttpTransport? transport,
  }) : _baseUrl = 'http://$host:$port',
       _token = token, // ignore: prefer_initializing_formals
       _transport = transport ?? IoHttpTransport();

  // -------------------------------------------------------------------------
  // Request helpers
  // -------------------------------------------------------------------------

  /// Default headers sent on every request (including the public `/health`).
  Map<String, String> get _defaultHeaders => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/json',
  };

  /// Headers for requests that send a JSON body (POST with a body).
  Map<String, String> get _jsonHeaders => {
    ..._defaultHeaders,
    'Content-Type': 'application/json',
  };

  /// Throw the appropriate typed error for a non-2xx status code; no-op
  /// (returns normally) for 2xx statuses.
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

  /// Parse a response body as a single JSON object and throw typed errors
  /// for non-2xx codes.
  T _decode<T>(
    int statusCode,
    String body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    _checkStatus(statusCode, body);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiError(statusCode: statusCode, body: 'invalid JSON: $body');
    }
    return fromJson(json);
  }

  /// Parse a response body as a JSON array and throw typed errors for
  /// non-2xx codes.
  List<T> _decodeList<T>(
    int statusCode,
    String body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    _checkStatus(statusCode, body);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      throw ApiError(statusCode: statusCode, body: 'invalid JSON: $body');
    }
    if (decoded is! List) {
      throw ApiError(
        statusCode: statusCode,
        body: 'expected JSON array: $body',
      );
    }
    return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
  }

  // -------------------------------------------------------------------------
  // v0 endpoints
  // -------------------------------------------------------------------------

  /// `GET /health` — server liveness probe.
  ///
  /// Returns [HealthDto] on success. `/health` is a public route (no bearer
  /// required), but the header is sent anyway (harmless per spec).
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors,
  /// or a [SocketException] / [HttpException] on network failure.
  Future<HealthDto> getHealth() async {
    final result = await _transport.get(
      '$_baseUrl/health',
      headers: _defaultHeaders,
    );
    return _decode(result.statusCode, result.body, HealthDto.fromJson);
  }

  // -------------------------------------------------------------------------
  // Session REST (v0.1) endpoints — serve-api.md §10
  // -------------------------------------------------------------------------

  /// `GET /api/sessions` — list all current tmux sessions.
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors
  /// (including tmux degradation per §10.4), or a [SocketException] /
  /// [HttpException] on network failure.
  Future<List<SessionDto>> getSessions() async {
    final result = await _transport.get(
      '$_baseUrl/api/sessions',
      headers: _defaultHeaders,
    );
    return _decodeList(result.statusCode, result.body, SessionDto.fromJson);
  }

  /// `GET /api/sessions/{name}/pane` — read pane output for [name].
  ///
  /// [lines], if given, caps the number of trailing lines returned; omit to
  /// return all non-blank lines.
  ///
  /// Throws [ApiError] with a `404` status when the session does not exist.
  Future<PaneDto> getPane(String name, {int? lines}) async {
    final encodedName = Uri.encodeComponent(name);
    var url = '$_baseUrl/api/sessions/$encodedName/pane';
    if (lines != null) {
      url = '$url?lines=$lines';
    }
    final result = await _transport.get(url, headers: _defaultHeaders);
    return _decode(result.statusCode, result.body, PaneDto.fromJson);
  }

  /// `POST /api/sessions/{name}/send` — send a literal key sequence
  /// (followed by `Enter`) to session [name].
  ///
  /// Returns normally on `204 No Content`. Throws [ApiError] with a `404`
  /// status when the session does not exist.
  Future<void> sendKeys(String name, String keys) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.post(
      '$_baseUrl/api/sessions/$encodedName/send',
      headers: _jsonHeaders,
      body: jsonEncode({'keys': keys}),
    );
    _checkStatus(result.statusCode, result.body);
  }

  /// `POST /api/sessions/{name}/key` — send a single symbolic tmux key
  /// name (e.g. `"Escape"`, `"Enter"`, `"C-c"`) to session [name].
  ///
  /// Returns normally on `204 No Content`. Throws [ApiError] with a `404`
  /// status when the session does not exist.
  Future<void> sendKey(String name, String key) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.post(
      '$_baseUrl/api/sessions/$encodedName/key',
      headers: _jsonHeaders,
      body: jsonEncode({'key': key}),
    );
    _checkStatus(result.statusCode, result.body);
  }

  /// `POST /api/sessions` — create a new detached tmux session named
  /// [name], optionally starting in [dir].
  ///
  /// Returns normally on `201 Created`. Throws [ApiError] with a `500`
  /// status when the session name is already in use.
  Future<void> createSession(String name, {String? dir}) async {
    final result = await _transport.post(
      '$_baseUrl/api/sessions',
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'dir': ?dir}),
    );
    _checkStatus(result.statusCode, result.body);
  }

  /// `DELETE /api/sessions/{name}` — kill session [name].
  ///
  /// Returns normally on `204 No Content`. Throws [ApiError] with a `404`
  /// status when the session does not exist.
  Future<void> deleteSession(String name) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.delete(
      '$_baseUrl/api/sessions/$encodedName',
      headers: _defaultHeaders,
    );
    _checkStatus(result.statusCode, result.body);
  }

  // -------------------------------------------------------------------------
  // Repo/workflow status REST (v0.3) endpoints — serve-api.md §11
  // -------------------------------------------------------------------------

  /// `GET /api/repos` — list every workspace-registry repo.
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<List<RepoSummaryDto>> getRepos() async {
    final result = await _transport.get(
      '$_baseUrl/api/repos',
      headers: _defaultHeaders,
    );
    return _decodeList(result.statusCode, result.body, RepoSummaryDto.fromJson);
  }

  /// `GET /api/repos/{name}/status` — the parsed `status.md` for repo
  /// [name].
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<RepoStatusDto> getRepoStatus(String name) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.get(
      '$_baseUrl/api/repos/$encodedName/status',
      headers: _defaultHeaders,
    );
    return _decode(result.statusCode, result.body, RepoStatusDto.fromJson);
  }

  /// `GET /api/repos/{name}/handoff` — the parsed `handoff.md` for repo
  /// [name].
  ///
  /// Returns `null` when the repo has no `handoff.md` (a `404` with code
  /// `C002` — a legitimate, non-error state, not thrown as [ApiError]).
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on any other HTTP error,
  /// or a [SocketException] / [HttpException] on network failure.
  Future<HandoffInfo?> getRepoHandoff(String name) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.get(
      '$_baseUrl/api/repos/$encodedName/handoff',
      headers: _defaultHeaders,
    );
    if (result.statusCode == 404) {
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(result.body) as Map<String, dynamic>;
      } catch (_) {
        json = null;
      }
      if (json != null && json['code'] == 'C002') {
        return null;
      }
      throw ApiError(statusCode: result.statusCode, body: result.body);
    }
    return _decode(result.statusCode, result.body, HandoffInfo.fromJson);
  }

  /// `GET /api/repos/{name}/workflows` — every in-flight/completed SDLC
  /// workflow for repo [name].
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<List<WorkflowStateDto>> getRepoWorkflows(String name) async {
    final encodedName = Uri.encodeComponent(name);
    final result = await _transport.get(
      '$_baseUrl/api/repos/$encodedName/workflows',
      headers: _defaultHeaders,
    );
    return _decodeList(
      result.statusCode,
      result.body,
      WorkflowStateDto.fromJson,
    );
  }

  // -------------------------------------------------------------------------
  // Quick-action command REST (v0.5) — serve-api.md §12
  // -------------------------------------------------------------------------

  /// `POST /api/actions/command` — fire a slash-command at Bastion, either
  /// injecting it into an existing session ([CommandMode.inject]) or
  /// spawning a new one ([CommandMode.spawn]).
  ///
  /// Note the `/api` prefix: the master-plan's shorthand `POST
  /// /actions/command` omits it — the contract (serve-api.md §12) wins.
  ///
  /// Returns the target tmux session id from the `200` response body.
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors
  /// (`400`/`C006` bad mode/field combo or untrusted spawn dir, `404`/`C002`
  /// inject into an unknown session, `503`/`C001` tmux unavailable,
  /// `504`/`C007` spawn readiness timeout, `500`/`C010` otherwise per
  /// §12.3), or a [SocketException] / [HttpException] on network failure.
  Future<String> postCommand(CommandRequest request) async {
    final result = await _transport.post(
      '$_baseUrl/api/actions/command',
      headers: _jsonHeaders,
      body: jsonEncode(request.toJson()),
    );
    final response = _decode(
      result.statusCode,
      result.body,
      CommandResponse.fromJson,
    );
    return response.session;
  }

  // -------------------------------------------------------------------------
  // Board / Attention / Docs read surfaces (v0.30) — serve-api.md §13, §15, §16
  // -------------------------------------------------------------------------
  //
  // All four routes below are on the CONSOLE surface: `/api` prefix,
  // `Authorization: Bearer` header — never confuse with the engine mount
  // (no `/api` prefix, `X-API-Key` header), which is BU.12.A.

  /// `GET /api/board` — the now/next/blocked/deferred/finished lanes for the
  /// given scope (serve-api.md §13).
  ///
  /// Only the parameters actually supplied are emitted as query params.
  /// [graph] defaults to `false`; passing `true` emits `?graph=true`, which
  /// roughly doubles this endpoint's wall-clock on the live HQ corpus — it
  /// must never be enabled by default.
  ///
  /// serve-api.md §13.1 documents `?graph=1` as an accepted alternate
  /// spelling, but the real server's query deserializer (BU.11.A Task 6
  /// e2e run against `bastion` main, 2026-08-14) only accepts the strict
  /// boolean strings `"true"`/`"false"` and returns `400` for `"1"` — see
  /// this spec's Amendment Log.
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<BoardDto> getBoard({
    String? scope,
    String? tier,
    String? repo,
    String? epic,
    bool graph = false,
  }) async {
    final params = <String, String>{
      'scope': ?scope,
      'tier': ?tier,
      'repo': ?repo,
      'epic': ?epic,
      if (graph) 'graph': 'true',
    };
    final url = _withQuery('$_baseUrl/api/board', params);
    final result = await _transport.get(url, headers: _defaultHeaders);
    return _decode(result.statusCode, result.body, BoardDto.fromJson);
  }

  /// `GET /api/attention` — the stale-carryover, aging-backlog and
  /// orphaned-captures lanes for the given scope (serve-api.md §15).
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<AttentionDto> getAttention({String? scope, String? tier}) async {
    final params = <String, String>{'scope': ?scope, 'tier': ?tier};
    final url = _withQuery('$_baseUrl/api/attention', params);
    final result = await _transport.get(url, headers: _defaultHeaders);
    return _decode(result.statusCode, result.body, AttentionDto.fromJson);
  }

  /// `GET /api/docs/{repo}/tree` — the allowlisted markdown tree for
  /// [repo], optionally rooted at [path] (serve-api.md §16.1).
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors
  /// (including a rejected traversal path per §16.2), or a
  /// [SocketException] / [HttpException] on network failure.
  Future<DocTreeDto> getDocsTree(String repo, {String? path}) async {
    final encodedRepo = Uri.encodeComponent(repo);
    final params = <String, String>{'path': ?path};
    final url = _withQuery('$_baseUrl/api/docs/$encodedRepo/tree', params);
    final result = await _transport.get(url, headers: _defaultHeaders);
    return _decode(result.statusCode, result.body, DocTreeDto.fromJson);
  }

  /// `GET /api/docs/{repo}/file` — the raw markdown content of [path]
  /// within [repo] (serve-api.md §16.2).
  ///
  /// The server owns path-traversal rejection; this client sends [path]
  /// as-is and surfaces any rejection as [ApiError].
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<DocFileDto> getDocsFile(String repo, {required String path}) async {
    final encodedRepo = Uri.encodeComponent(repo);
    final params = <String, String>{'path': path};
    final url = _withQuery('$_baseUrl/api/docs/$encodedRepo/file', params);
    final result = await _transport.get(url, headers: _defaultHeaders);
    return _decode(result.statusCode, result.body, DocFileDto.fromJson);
  }

  // -------------------------------------------------------------------------
  // Live runs read surface (v0.16 / v0.17 / v0.22) — serve-api.md §14
  // -------------------------------------------------------------------------
  //
  // BEARER AUTH ONLY, like the block above — never the engine `X-API-Key`
  // (that key is BU.12.A/D/E's, for control/launch, not for these read
  // routes; see this block's task 2 description).

  /// `GET /api/runs` — every currently-tracked run
  /// (`LiveStateStore::list_active()`, serve-api.md §14.1).
  ///
  /// A `200 []` response is a valid, expected success — it means no engine
  /// is mounted or nothing is running, never an error.
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<List<RunSummaryDto>> getRuns() async {
    final result = await _transport.get(
      '$_baseUrl/api/runs',
      headers: _defaultHeaders,
    );
    return _decodeList(result.statusCode, result.body, RunSummaryDto.fromJson);
  }

  /// `GET /api/runs/{id}` — the per-node snapshot for run [runId]
  /// (serve-api.md §14.2).
  ///
  /// Throws [FatalAuthError] on `401`, [ApiError] on other HTTP errors, or a
  /// [SocketException] / [HttpException] on network failure.
  Future<RunStateDto> getRun(String runId) async {
    final encodedRunId = Uri.encodeComponent(runId);
    final result = await _transport.get(
      '$_baseUrl/api/runs/$encodedRunId',
      headers: _defaultHeaders,
    );
    return _decode(result.statusCode, result.body, RunStateDto.fromJson);
  }

  /// Append [params] to [base] as a URL-encoded query string; returns
  /// [base] unchanged when [params] is empty.
  static String _withQuery(String base, Map<String, String> params) {
    if (params.isEmpty) return base;
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$base?$query';
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
