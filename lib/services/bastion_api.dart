/// REST client for `bastion serve` — v0 surface only.
///
/// Implements the v0 HTTP surface from serve-api.md (v0.1):
///   - `GET /health` → [HealthDto]  (public — no bearer required, but harmless to send)
///
/// A `401` response is decoded as a typed [FatalAuthError] and rethrown;
/// the caller must not retry after receiving [FatalAuthError].
///
/// Session REST routes (§6, v0.1) are Phase 1+ — **out of scope here**.
library;

import 'dart:convert';
import 'dart:io';

import '../models/dto.dart';

// ---------------------------------------------------------------------------
// Transport abstraction (enables unit testing without a real network)
// ---------------------------------------------------------------------------

/// Minimal HTTP GET interface used by [BastionApi].
///
/// The default implementation uses [dart:io]'s [HttpClient].
/// Tests may supply a [FakeHttpTransport].
abstract interface class HttpTransport {
  /// Perform a GET request and return the response status code + body.
  Future<({int statusCode, String body})> get(
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

  /// Parse a response and throw typed errors for non-2xx codes.
  T _decode<T>(
    int statusCode,
    String body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
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
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiError(statusCode: statusCode, body: 'invalid JSON: $body');
    }
    return fromJson(json);
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
