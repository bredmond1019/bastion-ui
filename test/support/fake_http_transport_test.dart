// Self-test of the shared routing fake (BU.ticket.integration-test-tier
// task 1). Exercises the fixture in isolation, with no real BastionApi
// involved, so a bug in the fixture itself is caught here rather than
// surfacing confusingly in the integration tier that depends on it.

import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('FakeHttpTransport', () {
    test('a registered route returns its body', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 200, body: {'repos': []});

      final response = await t.get('http://127.0.0.1:4317/api/repos');

      expect(response.statusCode, 200);
      expect(response.body, '{"repos":[]}');
    });

    test('an unmatched request fails the test loudly', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 200, body: {'repos': []});

      // The GET route is registered but not POST — same path, wrong verb.
      await expectLater(
        () => t.post('http://127.0.0.1:4317/api/repos', body: '{}'),
        throwsA(isA<TestFailure>()),
      );
    });

    test('an unmatched path fails the test loudly', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 200, body: {'repos': []});

      await expectLater(
        () => t.get('http://127.0.0.1:4317/api/sessions'),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('GET'),
              contains('/api/sessions'),
              contains('/api/repos'),
            ),
          ),
        ),
      );
    });

    test('never falls through to another route\'s body', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/repos', status: 200, body: {'kind': 'repos'});
      t.on('GET', '/api/sessions', status: 200, body: {'kind': 'sessions'});

      final reposResponse = await t.get('http://127.0.0.1:4317/api/repos');
      final sessionsResponse = await t.get(
        'http://127.0.0.1:4317/api/sessions',
      );

      expect(reposResponse.body, contains('repos'));
      expect(sessionsResponse.body, contains('sessions'));
    });

    test('query parameters and headers are recorded', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/pane', status: 200, body: {'ok': true});

      await t.get(
        'http://127.0.0.1:4317/api/pane?session=abc&lines=50',
        headers: {'Authorization': 'Bearer test-token'},
      );

      final call = t.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/api/pane');
      expect(call.queryParameters, {'session': 'abc', 'lines': '50'});
      expect(call.headers['Authorization'], 'Bearer test-token');
    });

    test('query strings never defeat a route match', () async {
      final t = FakeHttpTransport();
      t.on('GET', '/api/pane', status: 200, body: {'ok': true});

      final response = await t.get(
        'http://127.0.0.1:4317/api/pane?session=abc',
      );

      expect(response.statusCode, 200);
    });

    test('a two-response sequence is consumed in order', () async {
      final t = FakeHttpTransport();
      t.onSequence('GET', '/api/repos', [
        (status: 500, body: {'error': 'boom'}),
        (status: 200, body: {'repos': []}),
      ]);

      final first = await t.get('http://127.0.0.1:4317/api/repos');
      final second = await t.get('http://127.0.0.1:4317/api/repos');

      expect(first.statusCode, 500);
      expect(second.statusCode, 200);
    });

    test('a sequence repeats its final response once exhausted', () async {
      final t = FakeHttpTransport();
      t.onSequence('GET', '/api/repos', [
        (status: 200, body: {'repos': []}),
      ]);

      await t.get('http://127.0.0.1:4317/api/repos');
      final third = await t.get('http://127.0.0.1:4317/api/repos');

      expect(third.statusCode, 200);
    });

    test('per-route call counter tracks invocations', () async {
      final t = FakeHttpTransport();
      t.on('DELETE', '/api/sessions/1', status: 204, body: '');

      expect(t.callCount('DELETE', '/api/sessions/1'), 0);
      await t.delete('http://127.0.0.1:4317/api/sessions/1');
      await t.delete('http://127.0.0.1:4317/api/sessions/1');
      expect(t.callCount('DELETE', '/api/sessions/1'), 2);
    });

    test('lastCallTo returns the most recent matching call', () async {
      final t = FakeHttpTransport();
      t.on('POST', '/api/sessions', status: 200, body: {'id': 'first'});

      await t.post(
        'http://127.0.0.1:4317/api/sessions',
        body: '{"name":"one"}',
      );
      await t.post(
        'http://127.0.0.1:4317/api/sessions',
        body: '{"name":"two"}',
      );

      final last = t.lastCallTo('POST', '/api/sessions');
      expect(last, isNotNull);
      expect(last!.body, '{"name":"two"}');
      expect(t.lastCallTo('GET', '/api/sessions'), isNull);
    });
  });
}
