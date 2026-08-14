// Kit-level guard tests for the BU.13.A instrument primitive kit
// (`BU.13.A` task 7). These pin properties that hold across the whole kit
// rather than any one widget:
//
//   1. No `Color(0x...)` literal exists anywhere under
//      `lib/widgets/instrument/` — modelled on the existing source-sweep
//      guard `test/theme/no_color_literals_test.dart` (same normalization,
//      same offender-naming failure message).
//   2. The barrel `lib/widgets/instrument/instrument.dart` exports every
//      primitive file in the directory — read off disk, so a seventh
//      primitive added later cannot be silently unexported.
//   3. Every primitive renders inside a bare `MaterialApp` on
//      `AppTheme.dark` without throwing, given representative empty/zero
//      inputs — the cheap smoke test that catches a primitive that only
//      works with populated data.
//
// A screens-diff guard does NOT belong here (task 8's job, scoped to this
// spec's own commit range) — a tree-wide guard cannot pass in a shared
// index with concurrent lanes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/brand/status_pill.dart';
import 'package:bastion_ui/widgets/instrument/instrument.dart';

const String _instrumentDirPath = 'lib/widgets/instrument';

void main() {
  group('instrument kit guards', () {
    test('no Color(0x...) literal exists under lib/widgets/instrument/', () {
      final dir = Directory(_instrumentDirPath);
      expect(
        dir.existsSync(),
        isTrue,
        reason: '$_instrumentDirPath must exist',
      );

      final literalPattern = RegExp(r'Color\(0x');
      final offenders = <String>[];

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final normalized = entity.path.replaceAll(r'\', '/');
        final libIndex = normalized.indexOf('lib/');
        final relPath = libIndex == -1
            ? normalized
            : normalized.substring(libIndex + 'lib/'.length);

        final content = entity.readAsStringSync();
        final lines = content.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (literalPattern.hasMatch(lines[i])) {
            offenders.add('lib/$relPath:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Found Color(0x...) literal(s) under lib/widgets/instrument/ — '
            'read from AppTokens/StatusTones instead:\n${offenders.join('\n')}',
      );
    });

    test(
      'the barrel exports every primitive file in lib/widgets/instrument/',
      () {
        final dir = Directory(_instrumentDirPath);
        expect(
          dir.existsSync(),
          isTrue,
          reason: '$_instrumentDirPath must exist',
        );

        final barrelFile = File('$_instrumentDirPath/instrument.dart');
        expect(
          barrelFile.existsSync(),
          isTrue,
          reason: '$_instrumentDirPath/instrument.dart (the barrel) must exist',
        );
        final barrelContent = barrelFile.readAsStringSync();

        final exportPattern = RegExp("export\\s+'([^']+)'");
        final exported = exportPattern
            .allMatches(barrelContent)
            .map((m) => m.group(1)!)
            .toSet();

        final onDisk = dir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where(
              (name) => name.endsWith('.dart') && name != 'instrument.dart',
            )
            .toSet();

        final unexported = onDisk.difference(exported);

        expect(
          unexported,
          isEmpty,
          reason:
              'Found primitive file(s) under lib/widgets/instrument/ not '
              'exported by the barrel: ${unexported.join(', ')}',
        );
      },
    );

    group('every primitive renders without throwing on empty/zero inputs', () {
      testWidgets('AgeChip', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: AgeChip(age: Duration.zero)),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('StatTile', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: StatTile(value: '0', label: 'none'),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('LaneBar (all-zero counts)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: LaneBar(done: 0, now: 0, blocked: 0, next: 0),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Sparkline (empty series)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: Sparkline(values: <double>[])),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('SeverityRow', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SeverityRow(
                severity: SeverityRowSeverity.idle,
                title: '',
                pillTone: StatusPillTone.onTrack,
                pillLabel: '',
                meta: '',
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('GateCard (zero blast radius)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: GateCard(
                name: '',
                waitingOn: '',
                blastRadius: 0,
                onAct: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });
  });
}
