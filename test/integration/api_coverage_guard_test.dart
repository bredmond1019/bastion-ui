// Guard test (BU.ticket.integration-test-tier task 5): fails, naming the
// offending method(s), when a public `BastionApi` method has no reference
// under test/integration/.
//
// This is a source sweep in the spirit of test/theme/no_color_literals_test
// .dart, not reflection (Dart's mirrors are unavailable in Flutter tests).
// It exists because a route added to lib/services/bastion_api.dart without
// a matching integration test is exactly the drift this tier is meant to
// catch: the request-shape/decode contract would silently stop being
// exercised outside the (non-gating) e2e tier.
//
// Only methods that actually perform a network call are in scope — they
// are the ones that return a `Future` and represent a route on the wire.
// `dispose()` (lifecycle, no HTTP call) and private/static helpers are
// deliberately excluded; policing them would make this guard demand
// integration coverage for things that are not routes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every public BastionApi route method is referenced under '
      'test/integration/', () {
    final apiFile = File('lib/services/bastion_api.dart');
    expect(
      apiFile.existsSync(),
      isTrue,
      reason: 'lib/services/bastion_api.dart must exist',
    );

    final source = apiFile.readAsStringSync();

    // Isolate the BastionApi class body only — the file also declares
    // HttpTransport and IoHttpTransport, whose get/post/delete members
    // must NOT be swept into this guard.
    final classStart = source.indexOf('final class BastionApi {');
    expect(
      classStart,
      greaterThanOrEqualTo(0),
      reason: 'final class BastionApi { declaration not found',
    );

    final bodyStart = source.indexOf('{', classStart) + 1;
    var depth = 1;
    var i = bodyStart;
    while (i < source.length && depth > 0) {
      final ch = source[i];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      i++;
    }
    final classBody = source.substring(bodyStart, i - 1);

    // Public, Future-returning method declarations only — these are the
    // routes. `Future<` may itself contain nested generics
    // (e.g. `Future<List<SessionDto>>`, `Future<HandoffInfo?>`), so match
    // up to the method name rather than trying to balance the generic.
    final methodPattern = RegExp(
      r'^\s{2}Future<[^(]*?>\s+([A-Za-z]\w*)\s*\(',
      multiLine: true,
    );

    final routeMethods = <String>{
      for (final m in methodPattern.allMatches(classBody)) m.group(1)!,
    }..removeWhere((name) => name.startsWith('_'));

    expect(
      routeMethods,
      isNotEmpty,
      reason:
          'no Future-returning public methods found on BastionApi — the '
          'scan pattern likely drifted from the source',
    );

    final integrationDir = Directory('test/integration');
    expect(
      integrationDir.existsSync(),
      isTrue,
      reason: 'test/integration/ must exist',
    );

    final integrationSource = StringBuffer();
    for (final entity in integrationDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        integrationSource.write(entity.readAsStringSync());
        integrationSource.write('\n');
      }
    }
    final haystack = integrationSource.toString();

    final uncovered = <String>[];
    for (final name in routeMethods) {
      // Require a call-shaped reference (`.name(` or `name(`), not a
      // bare substring hit, so a method name that happens to appear
      // inside an unrelated comment/string doesn't count as coverage.
      final callPattern = RegExp(
        r'(?<![A-Za-z0-9_])' + RegExp.escape(name) + r'\s*\(',
      );
      if (!callPattern.hasMatch(haystack)) {
        uncovered.add(name);
      }
    }
    uncovered.sort();

    expect(
      uncovered,
      isEmpty,
      reason:
          'BastionApi method(s) with no reference under '
          'test/integration/: ${uncovered.join(', ')}. Add a fixture '
          '(test/support/wire_fixtures.dart), a case in '
          'bastion_api_integration_test.dart, and (non-gating) an e2e '
          'case for each new route.',
    );
  });
}
