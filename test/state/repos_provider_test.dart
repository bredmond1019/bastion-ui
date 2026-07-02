// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/repos_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;

// ---------------------------------------------------------------------------
// Fake transport (mirrors sessions_provider_test.dart's fixture)
// ---------------------------------------------------------------------------

class FakeHttpTransport implements HttpTransport {
  final List<({int statusCode, String body})> _responses = [];
  int getCallCount = 0;

  void setResponse({required int statusCode, required Object body}) {
    final encoded = body is String ? body : jsonEncode(body);
    _responses.add((statusCode: statusCode, body: encoded));
  }

  @override
  Future<({int statusCode, String body})> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    getCallCount++;
    if (_responses.isEmpty) {
      throw StateError('FakeHttpTransport: no response queued for GET $url');
    }
    return _responses.removeAt(0);
  }

  @override
  Future<({int statusCode, String body})> post(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<({int statusCode, String body})> delete(
    String url, {
    Map<String, String> headers = const {},
  }) => throw UnimplementedError('not exercised by this test');
}

Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test('reposProvider throws StateError when read before connect', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(reposProvider), throwsA(isA<StateError>()));
  });

  group('reposProvider', () {
    late FakeHttpTransport httpTransport;
    late BastionApi api;
    late ProviderContainer container;

    setUp(() {
      httpTransport = FakeHttpTransport();
      api = BastionApi(
        host: 'test-host',
        port: 4317,
        token: 'test-token',
        transport: httpTransport,
      );
    });

    tearDown(() => container.dispose());

    test('seeds state from GET /api/repos on first watch', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {
            'name': 'bastion-ui',
            'now': 'wiring dashboard',
            'has_handoff': true,
          },
          {'name': 'bella', 'now': 'idle', 'has_handoff': false},
        ],
      );
      container = ProviderContainer(
        overrides: [bastionApiProvider.overrideWith((ref) => api)],
      );

      container.read(reposProvider);
      await pump();

      final repos = container.read(reposProvider);
      expect(repos, hasLength(2));
      expect(repos.map((r) => r.name), ['bastion-ui', 'bella']);
      expect(repos.first.hasHandoff, isTrue);
    });

    test('refresh() re-fetches and replaces state', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {'name': 'stale', 'now': 'old', 'has_handoff': false},
        ],
      );
      container = ProviderContainer(
        overrides: [bastionApiProvider.overrideWith((ref) => api)],
      );
      container.read(reposProvider);
      await pump();
      expect(container.read(reposProvider).single.name, 'stale');

      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {'name': 'fresh', 'now': 'new', 'has_handoff': true},
        ],
      );
      await container.read(reposProvider.notifier).refresh();

      expect(container.read(reposProvider).single.name, 'fresh');
    });

    test('a failed refresh() leaves the previous state in place', () async {
      httpTransport.setResponse(
        statusCode: 200,
        body: [
          {'name': 'kept', 'now': 'now', 'has_handoff': false},
        ],
      );
      container = ProviderContainer(
        overrides: [bastionApiProvider.overrideWith((ref) => api)],
      );
      container.read(reposProvider);
      await pump();
      expect(container.read(reposProvider).single.name, 'kept');

      httpTransport.setResponse(statusCode: 500, body: 'boom');
      await container.read(reposProvider.notifier).refresh();

      expect(container.read(reposProvider).single.name, 'kept');
    });
  });
}
