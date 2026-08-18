import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/board_dto.dart';

import '../support/wire_fixtures.dart';

void main() {
  group('BoardBlockDto', () {
    test('fully-populated payload including all three graph fields', () {
      final block = BoardBlockDto.fromJson({
        'id': 'BA.11.K',
        'title': 'Cross-brain board read endpoint',
        'repo': 'bastion',
        'status': 'in_progress',
        'blocked_by': [
          {'type': 'block', 'repo': 'mev', 'id': 'MV.10.B', 'what': 'blocks'},
        ],
        'epics': ['bastion-surfaces'],
        'wave': 3,
        'dependent_count': 4,
        'ready': true,
        'unmet_count': 0,
      });

      expect(block.id, 'BA.11.K');
      expect(block.title, 'Cross-brain board read endpoint');
      expect(block.repo, 'bastion');
      expect(block.status, 'in_progress');
      expect(block.blockedBy, hasLength(1));
      expect(block.blockedBy.single, isA<BlockDepDto>());
      expect(block.epics, ['bastion-surfaces']);
      expect(block.wave, 3);
      expect(block.dependentCount, 4);
      expect(block.ready, isTrue);
      expect(block.unmetCount, 0);
    });

    test('payload WITH last_touched decodes to a known DateTime', () {
      final block = BoardBlockDto.fromJson(boardBlockFullFixture);

      expect(block.lastTouched, isNotNull);
      expect(block.lastTouched, DateTime.parse('2026-08-10T12:00:00Z'));
    });

    test('payload WITHOUT last_touched at all: null, never-worked, '
        'does not throw', () {
      final block = BoardBlockDto.fromJson(boardBlockMinimalFixture);

      expect(block.lastTouched, isNull);
    });

    test('some blocks have last_touched and some do not — each decodes '
        'independently without conflating absence with the other', () {
      final withTouch = BoardBlockDto.fromJson(boardBlockFullFixture);
      final withoutTouch = BoardBlockDto.fromJson(boardBlockMinimalFixture);

      expect(withTouch.lastTouched, isNotNull);
      expect(withoutTouch.lastTouched, isNull);
    });

    test('v0.11/v0.33/v0.34 fields decode from the full fixture', () {
      final block = BoardBlockDto.fromJson(boardBlockFullFixture);

      expect(block.priority, 1);
      expect(block.due, '2026-07-15');
      expect(block.track, 'Phase 11');
      expect(block.effectivePriority, 1);
      expect(
        block.description,
        'Cross-brain board read endpoint, full description.',
      );
      expect(block.created, '2026-06-01');
      expect(block.closedDate, '2026-08-05');
      expect(block.commit, 'abc123def');
      expect(block.origin?.kind, 'carryover');
      expect(block.origin?.slug, 'BU.carryover.board-drift');
    });

    test('v0.11/v0.33/v0.34 fields absent from the minimal fixture', () {
      final block = BoardBlockDto.fromJson(boardBlockMinimalFixture);

      expect(block.priority, isNull);
      expect(block.due, isNull);
      expect(block.track, isNull);
      expect(block.effectivePriority, isNull);
      expect(block.description, isNull);
      expect(block.created, isNull);
      expect(block.closedDate, isNull);
      expect(block.commit, isNull);
      expect(block.origin, isNull);
    });

    test('same payload without ?graph=1: all three graph fields null, '
        'distinguishable from zero/false', () {
      final block = BoardBlockDto.fromJson({
        'id': 'BA.11.D',
        'title': 'Repo status REST surface',
        'repo': 'bastion',
        'status': 'closed',
        'blocked_by': [],
        'epics': [],
        'wave': null,
      });

      expect(block.dependentCount, isNull);
      expect(block.ready, isNull);
      expect(block.unmetCount, isNull);
      expect(block.lastTouched, isNull);
      // Explicitly assert null is not conflated with a falsy/zero value.
      expect(block.dependentCount == 0, isFalse);
      expect(block.ready == false, isFalse);
      expect(block.unmetCount == 0, isFalse);
    });

    test('minimal payload with every optional field absent', () {
      final block = BoardBlockDto.fromJson({
        'id': 'BA.1.A',
        'title': 'Minimal',
        'repo': 'bastion',
      });

      expect(block.status, isNull);
      expect(block.blockedBy, isEmpty);
      expect(block.epics, isEmpty);
      expect(block.wave, isNull);
      expect(block.dependentCount, isNull);
      expect(block.ready, isNull);
      expect(block.unmetCount, isNull);
      expect(block.lastTouched, isNull);
    });

    test('an unrecognised blocked_by entry shape decodes without throwing', () {
      final block = BoardBlockDto.fromJson({
        'id': 'BA.1.A',
        'title': 'Weird',
        'repo': 'bastion',
        'blocked_by': [
          {'type': 'future_variant', 'foo': 'bar'},
          {'type': 'block', 'repo': 'mev'}, // missing required "id"
          {'no_type_field': true},
          'not-even-a-map',
        ],
      });

      expect(block.blockedBy, hasLength(3));
      expect(block.blockedBy[0], isA<UnknownBlockedByDto>());
      expect(
        (block.blockedBy[0] as UnknownBlockedByDto).raw['type'],
        'future_variant',
      );
      expect(block.blockedBy[1], isA<UnknownBlockedByDto>());
      expect(block.blockedBy[2], isA<UnknownBlockedByDto>());
    });

    test('recognises external/operator/approval blocked_by variants', () {
      final block = BoardBlockDto.fromJson({
        'id': 'BA.1.A',
        'title': 'Multi-gate',
        'repo': 'bastion',
        'blocked_by': [
          {'type': 'external', 'what': 'waiting on a vendor API'},
          {
            'type': 'operator',
            'slug': 'decide-x',
            'exit': 'artifact exists',
            'start': '/begin-session decide-x',
          },
          {
            'type': 'approval',
            'slug': 'ship-it',
            'what': 'deploy to prod',
            'digest': 'abc123',
          },
        ],
      });

      expect(block.blockedBy[0], isA<ExternalDepDto>());
      expect(block.blockedBy[1], isA<OperatorDepDto>());
      expect(block.blockedBy[2], isA<ApprovalDepDto>());
    });
  });

  group('BoardLaneDto', () {
    test('every lane array absent defaults to empty lists', () {
      final lanes = BoardLaneDto.fromJson(const {});

      expect(lanes.now, isEmpty);
      expect(lanes.next, isEmpty);
      expect(lanes.blocked, isEmpty);
      expect(lanes.deferred, isEmpty);
      expect(lanes.finished, isEmpty);
    });

    test('fully-populated lanes decode each list', () {
      Map<String, dynamic> block(String id) => {
        'id': id,
        'title': id,
        'repo': 'bastion',
      };
      final lanes = BoardLaneDto.fromJson({
        'now': [block('A')],
        'next': [block('B')],
        'blocked': [block('C')],
        'deferred': [block('D')],
        'finished': [block('E')],
      });

      expect(lanes.now.single.id, 'A');
      expect(lanes.next.single.id, 'B');
      expect(lanes.blocked.single.id, 'C');
      expect(lanes.deferred.single.id, 'D');
      expect(lanes.finished.single.id, 'E');
    });
  });

  group('BoardDto', () {
    test('fully-populated payload with repos and stale flag', () {
      final board = BoardDto.fromJson({
        'scope': 'project',
        'tier': 'core',
        'lanes': {
          'now': [
            {'id': 'A', 'title': 'A', 'repo': 'bastion'},
          ],
        },
        'repos': [
          {
            'repo': 'bastion',
            'tier': 'core',
            'lanes': {
              'now': [
                {'id': 'A', 'title': 'A', 'repo': 'bastion'},
              ],
            },
          },
        ],
        'stale': true,
      });

      expect(board.scope, 'project');
      expect(board.tier, 'core');
      expect(board.lanes.now, hasLength(1));
      expect(board.repos, hasLength(1));
      expect(board.repos.single.repo, 'bastion');
      expect(board.repos.single.lanes.now.single.id, 'A');
      expect(board.stale, isTrue);
    });

    test('minimal payload: everything absent decodes to safe defaults', () {
      final board = BoardDto.fromJson(const {});

      expect(board.scope, isNull);
      expect(board.tier, isNull);
      expect(board.lanes.now, isEmpty);
      expect(board.repos, isEmpty);
      expect(board.stale, isFalse);
    });

    test('empty-collection payload: explicit empty lanes/repos', () {
      final board = BoardDto.fromJson(const {
        'lanes': {
          'now': <Map<String, dynamic>>[],
          'next': <Map<String, dynamic>>[],
          'blocked': <Map<String, dynamic>>[],
          'deferred': <Map<String, dynamic>>[],
          'finished': <Map<String, dynamic>>[],
        },
        'repos': <Map<String, dynamic>>[],
        'stale': false,
      });

      expect(board.lanes.now, isEmpty);
      expect(board.repos, isEmpty);
      expect(board.stale, isFalse);
    });
  });
}
