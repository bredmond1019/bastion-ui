import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/attention_dto.dart';

void main() {
  group('AttentionCarryoverDto', () {
    test('fully-populated payload', () {
      final carryover = AttentionCarryoverDto.fromJson({
        'repo': 'bastion',
        'slug': 'serve-attention-endpoint',
        'kind': 'deferred',
        'text': 'Wire up the attention projection.',
        'clears_when': 'BU.11.A ships',
        'created': '2026-07-10',
        'reviewed': '2026-07-20',
        'age_days': 14,
        'threshold_days': 7,
        'lane': 'hot',
        'priority': 2,
        'effective_priority': 1,
        'unmet_blocks': ['BA.10.A'],
        'finding_id': 'F-123',
        'clears_when_satisfied': false,
      });

      expect(carryover.repo, 'bastion');
      expect(carryover.slug, 'serve-attention-endpoint');
      expect(carryover.kind, 'deferred');
      expect(carryover.text, 'Wire up the attention projection.');
      expect(carryover.clearsWhen, 'BU.11.A ships');
      expect(carryover.created, '2026-07-10');
      expect(carryover.reviewed, '2026-07-20');
      expect(carryover.ageDays, 14);
      expect(carryover.thresholdDays, 7);
      expect(carryover.lane, 'hot');
      expect(carryover.priority, 2);
      expect(carryover.effectivePriority, 1);
      expect(carryover.unmetBlocks, ['BA.10.A']);
      expect(carryover.findingId, 'F-123');
      expect(carryover.clearsWhenSatisfied, isFalse);
    });

    test('minimal payload with every optional field absent', () {
      final carryover = AttentionCarryoverDto.fromJson({
        'repo': 'bastion',
        'slug': 'minimal',
        'kind': 'env',
        'text': 'Some env note.',
        'threshold_days': 30,
        'lane': 'standing',
        'clears_when_satisfied': true,
      });

      expect(carryover.clearsWhen, isNull);
      expect(carryover.created, isNull);
      expect(carryover.reviewed, isNull);
      expect(carryover.ageDays, isNull);
      expect(carryover.priority, isNull);
      expect(carryover.effectivePriority, isNull);
      expect(carryover.unmetBlocks, isEmpty);
      expect(carryover.findingId, isNull);
      expect(carryover.clearsWhenSatisfied, isTrue);
    });

    test('null ageDays decodes and the entry remains present in the list', () {
      final lanes = AttentionLanesDto.fromJson({
        'stale_carryover': [
          {
            'repo': 'bastion',
            'slug': 'snoozed-item',
            'kind': 'constraint',
            'text': 'Snoozed, no anchor date.',
            'threshold_days': 14,
            'lane': 'aging',
            'clears_when_satisfied': false,
            // age_days deliberately absent — snoozed entry.
          },
        ],
      });

      expect(lanes.staleCarryover, hasLength(1));
      final entry = lanes.staleCarryover.single;
      expect(entry.ageDays, isNull);
      // Explicitly assert null is not conflated with zero.
      expect(entry.ageDays == 0, isFalse);
      expect(entry.slug, 'snoozed-item');
    });
  });

  group('AttentionBacklogDto', () {
    test('fully-populated payload', () {
      final backlog = AttentionBacklogDto.fromJson({
        'repo': 'bastion',
        'slug': 'serve-attention-endpoint',
        'title': 'Attention projection',
        'kind': 'feature',
        'status': 'ready',
        'notes': 'Some notes.',
        'created': '2026-07-10',
        'reviewed': null,
        'age_days': 14,
        'threshold_days': 7,
      });

      expect(backlog.repo, 'bastion');
      expect(backlog.slug, 'serve-attention-endpoint');
      expect(backlog.title, 'Attention projection');
      expect(backlog.kind, 'feature');
      expect(backlog.status, 'ready');
      expect(backlog.notes, 'Some notes.');
      expect(backlog.created, '2026-07-10');
      expect(backlog.reviewed, isNull);
      expect(backlog.ageDays, 14);
      expect(backlog.thresholdDays, 7);
    });

    test('minimal payload with every optional field absent', () {
      final backlog = AttentionBacklogDto.fromJson({
        'repo': 'bastion',
        'slug': 'minimal',
        'title': 'Minimal',
        'kind': 'feature',
        'status': 'idea',
        'age_days': 3,
        'threshold_days': 7,
      });

      expect(backlog.notes, isNull);
      expect(backlog.created, isNull);
      expect(backlog.reviewed, isNull);
    });
  });

  group('AttentionLanesDto', () {
    test('all three lane arrays absent default to empty lists', () {
      final lanes = AttentionLanesDto.fromJson(<String, dynamic>{});

      expect(lanes.staleCarryover, isEmpty);
      expect(lanes.agingBacklog, isEmpty);
      expect(lanes.orphanedCaptures, isEmpty);
    });

    test(
      'aging_backlog and orphaned_captures both decode to AttentionBacklogDto',
      () {
        final lanes = AttentionLanesDto.fromJson({
          'aging_backlog': [
            {
              'repo': 'bastion',
              'slug': 'aging-1',
              'title': 'Aging item',
              'kind': 'feature',
              'status': 'ready',
              'age_days': 10,
              'threshold_days': 7,
            },
          ],
          'orphaned_captures': [
            {
              'repo': 'bastion',
              'slug': 'orphan-1',
              'title': 'Orphaned capture',
              'kind': 'capture',
              'status': 'idea',
              'age_days': 20,
              'threshold_days': 7,
            },
          ],
        });

        expect(lanes.agingBacklog, hasLength(1));
        expect(lanes.orphanedCaptures, hasLength(1));
        expect(lanes.agingBacklog.single, isA<AttentionBacklogDto>());
        expect(lanes.orphanedCaptures.single, isA<AttentionBacklogDto>());
      },
    );
  });

  group('AttentionThresholdsDto', () {
    test('fully-populated payload', () {
      final thresholds = AttentionThresholdsDto.fromJson({
        'env_days': 30,
        'deferred_days': 14,
        'known_issue_days': 21,
        'constraint_days': 60,
        'backlog_days': 7,
      });

      expect(thresholds.envDays, 30);
      expect(thresholds.deferredDays, 14);
      expect(thresholds.knownIssueDays, 21);
      expect(thresholds.constraintDays, 60);
      expect(thresholds.backlogDays, 7);
    });
  });

  group('AttentionDto', () {
    test('fully-populated payload', () {
      final attention = AttentionDto.fromJson({
        'scope': 'hq',
        'tier': 'core',
        'as_of': '2026-08-14',
        'lanes': {
          'stale_carryover': [
            {
              'repo': 'bastion',
              'slug': 'a',
              'kind': 'env',
              'text': 'text',
              'threshold_days': 30,
              'lane': 'blocking',
              'clears_when_satisfied': false,
            },
          ],
        },
        'thresholds': {
          'env_days': 30,
          'deferred_days': 14,
          'known_issue_days': 21,
          'constraint_days': 60,
          'backlog_days': 7,
        },
      });

      expect(attention.scope, 'hq');
      expect(attention.tier, 'core');
      expect(attention.asOf, '2026-08-14');
      expect(attention.lanes.staleCarryover, hasLength(1));
      expect(attention.thresholds.envDays, 30);
    });

    test('minimal payload with tier absent (hq scope)', () {
      final attention = AttentionDto.fromJson({
        'as_of': '2026-08-14',
        'lanes': <String, dynamic>{},
        'thresholds': {
          'env_days': 30,
          'deferred_days': 14,
          'known_issue_days': 21,
          'constraint_days': 60,
          'backlog_days': 7,
        },
      });

      expect(attention.scope, isNull);
      expect(attention.tier, isNull);
      expect(attention.lanes.staleCarryover, isEmpty);
      expect(attention.lanes.agingBacklog, isEmpty);
      expect(attention.lanes.orphanedCaptures, isEmpty);
    });
  });
}
