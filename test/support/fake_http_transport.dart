// Shared routing fake for [HttpTransport] (BU.ticket.integration-test-tier
// task 1).
//
// Unlike the FIFO `FakeHttpTransport` copies duplicated across
// `test/services/api_test.dart`, `test/state/*_provider_test.dart` and
// `test/main_wiring_test.dart`, this fake is method- and path-aware:
// responses are registered per `(method, path)` and a request that does not
// match a registered route fails the test loudly instead of silently
// consuming whatever response happens to be next in a queue. That is the
// property this ticket exists to add — see
// `planning/ticket-integration-test-tier/tasks.md`.
//
// Task 6 migrates the six existing FIFO copies onto this fixture; until then
// this file is additive and touches nothing under `lib/`.
library;

import 'dart:convert';

import 'package:bastion_ui/services/bastion_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// One recorded request made against a [FakeHttpTransport] route.
///
/// [path] is the decoded path component only (no query string — see
/// [queryParameters] for that). [headers] and [body] are exactly what the
/// caller passed to the transport method.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.url,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
  });

  final String method;
  final String url;
  final String path;
  final Map<String, String> queryParameters;
  final Map<String, String> headers;
  final String? body;
}

/// One registered `(method, path)` route on a [FakeHttpTransport].
class _RouteKey {
  _RouteKey(String method, this.path) : method = method.toUpperCase();

  final String method;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is _RouteKey && other.method == method && other.path == path;

  @override
  int get hashCode => Object.hash(method, path);

  @override
  String toString() => '$method $path';
}

/// Routing fake [HttpTransport] for the integration test tier.
///
/// Register responses with [on]; each request is matched by HTTP method and
/// the request URL's decoded path (query strings never affect the match).
/// An unmatched request throws a [TestFailure] naming the offending method,
/// full URL, and every route that *was* registered, so a misrouted client
/// call fails the test instead of silently returning some other route's
/// body.
///
/// A route may be registered with more than one response (via repeated
/// calls to [on] or via [onSequence]); each call to that route consumes the
/// next response in the sequence and the final response repeats once the
/// sequence is exhausted, mirroring real-server idempotent-retry behaviour
/// while still letting refresh/retry tests assert a specific ordering.
final class FakeHttpTransport implements HttpTransport {
  final Map<_RouteKey, List<({int statusCode, String body})>> _routes = {};
  final Map<_RouteKey, int> _callCounts = {};
  final List<RecordedRequest> calls = [];

  /// Register a response for `(method, path)`. Calling this more than once
  /// for the same route appends to that route's response sequence — see
  /// [onSequence] for registering several at once.
  void on(
    String method,
    String path, {
    required int status,
    required Object body,
  }) {
    final encoded = body is String ? body : jsonEncode(body);
    final key = _RouteKey(method, path);
    _routes.putIfAbsent(key, () => []).add((statusCode: status, body: encoded));
  }

  /// Register a sequence of differing responses for one route, consumed in
  /// order across successive calls (e.g. a first-call failure followed by a
  /// successful retry).
  void onSequence(
    String method,
    String path,
    List<({int status, Object body})> responses,
  ) {
    for (final r in responses) {
      on(method, path, status: r.status, body: r.body);
    }
  }

  /// How many times [method]/[path] has been called so far.
  int callCount(String method, String path) =>
      _callCounts[_RouteKey(method, path)] ?? 0;

  /// The most recent recorded call to `(method, path)`, or `null` if it was
  /// never called.
  RecordedRequest? lastCallTo(String method, String path) {
    final upper = method.toUpperCase();
    for (final call in calls.reversed) {
      if (call.method == upper && call.path == path) return call;
    }
    return null;
  }

  Future<({int statusCode, String body})> _dispatch(
    String method,
    String url, {
    required Map<String, String> headers,
    String? body,
  }) async {
    final uri = Uri.parse(url);
    calls.add(
      RecordedRequest(
        method: method,
        url: url,
        path: uri.path,
        queryParameters: uri.queryParameters,
        headers: headers,
        body: body,
      ),
    );

    final key = _RouteKey(method, uri.path);
    final responses = _routes[key];
    if (responses == null || responses.isEmpty) {
      final registered = _routes.keys.map((k) => k.toString()).join(', ');
      fail(
        'FakeHttpTransport: no route registered for $method ${uri.path} '
        '(full URL: $url). Registered routes: '
        '${registered.isEmpty ? '(none)' : registered}',
      );
    }

    final index = _callCounts[key] ?? 0;
    _callCounts[key] = index + 1;
    final response =
        responses[index < responses.length ? index : responses.length - 1];
    return response;
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) => _dispatch('GET', url, headers: headers);

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => _dispatch('POST', url, headers: headers, body: body);

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) => _dispatch('DELETE', url, headers: headers);
}
