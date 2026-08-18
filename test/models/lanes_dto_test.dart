import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/lanes_dto.dart';

import '../support/wire_fixtures.dart';

void main() {
  group('LanesDto', () {
    test('decodes derived_at, degraded, and every segment', () {
      final lanes = LanesDto.fromJson(lanesFixture);

      expect(lanes.derivedAt, '2026-08-18T10:00:00-07:00');
      expect(lanes.degraded, isFalse);
      expect(lanes.segments, hasLength(3));
    });

    test('a startable segment carries head and no reason', () {
      final segment = LaneSegmentDto.fromJson(laneSegmentStartableFixture);

      expect(segment.roadmap, 'engine-orchestration');
      expect(segment.lane, 'derive');
      expect(segment.segment, 0);
      expect(segment.repo, 'mev');
      expect(segment.head, 'mev:MV.13.C');
      expect(segment.availability, 'startable');
      expect(segment.reason, isNull);
      expect(segment.leverageLanesFreed, 2);
    });

    test('a done segment has absent head and reason, not null-as-zero', () {
      final segment = LaneSegmentDto.fromJson(laneSegmentDoneFixture);

      expect(segment.availability, 'done');
      expect(segment.head, isNull);
      expect(segment.reason, isNull);
      expect(segment.leverageLanesFreed, 0);
    });

    test('a held segment carries a reason', () {
      final segment = LaneSegmentDto.fromJson(laneSegmentHeldFixture);

      expect(segment.availability, 'held-block');
      expect(segment.reason, 'waiting on mev:MV.13.C');
    });

    test('empty segments list decodes cleanly (known-but-unmatched epic)', () {
      final lanes = LanesDto.fromJson(lanesEmptyFixture);

      expect(lanes.segments, isEmpty);
    });
  });
}
