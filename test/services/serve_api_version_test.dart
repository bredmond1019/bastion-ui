import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/services/serve_api_version.dart';

/// Path to the upstream `bastion` repo's serve-api contract doc, relative to
/// this repo's root (the working directory `flutter test` runs from).
const String _upstreamDocPath = '../bastion/docs/serve-api.md';

/// Extracts the contract version from the doc's H1 heading line (e.g.
/// `# serve-api — v0.31 Contract` -> `v0.31`).
///
/// Deliberately NOT the `**Version:**` line: at spec-authoring time that
/// line disagreed with the H1 (H1 said v0.30, `**Version:**` still said
/// v0.29). The H1 is the line the doc's own title tracks, so it is the more
/// reliable source even when the two lines later re-converge.
String? _versionFromH1(String contents) {
  final versionPattern = RegExp(r'v\d+\.\d+');
  for (final line in const LineSplitter().convert(contents)) {
    if (line.startsWith('# ')) {
      final match = versionPattern.firstMatch(line);
      return match?.group(0);
    }
  }
  return null;
}

void main() {
  group('kServeApiPin drift test', () {
    test('matches the upstream serve-api.md H1 version, or skips cleanly '
        'without a sibling bastion checkout', () {
      final upstreamDoc = File(_upstreamDocPath);

      // D64 un-gateable-AC rule: this test reads ANOTHER repo's working
      // tree. A clone without a sibling `bastion` checkout must not see
      // this test fail — that would redden the gating suite for a reason
      // unrelated to any change in THIS repo. Skip cleanly instead.
      if (!upstreamDoc.existsSync()) {
        markTestSkipped(
          'sibling bastion checkout not found at $_upstreamDocPath — '
          'skipping serve-api version drift check',
        );
        return;
      }

      final contents = upstreamDoc.readAsStringSync();
      final upstreamVersion = _versionFromH1(contents);

      expect(
        upstreamVersion,
        isNotNull,
        reason:
            'could not find a "# ... vX.Y ..." H1 heading in '
            '$_upstreamDocPath to compare against kServeApiPin',
      );

      expect(
        kServeApiPin,
        equals(upstreamVersion),
        reason:
            'lib/services/serve_api_version.dart pins kServeApiPin='
            '"$kServeApiPin" but $_upstreamDocPath\'s H1 line now says '
            '"$upstreamVersion" — the Dart model layer has drifted from '
            'the upstream serve-api contract and needs to be re-mirrored.',
      );
    });
  });
}
