import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';

void main() {
  // -------------------------------------------------------------------------
  // RepoSummaryDto
  // -------------------------------------------------------------------------
  group('RepoSummaryDto', () {
    test('fromJson decodes name/now/has_handoff', () {
      final dto = RepoSummaryDto.fromJson({
        'name': 'bastion-ui',
        'now': 'wiring dashboard',
        'has_handoff': true,
      });
      expect(dto.name, 'bastion-ui');
      expect(dto.now, 'wiring dashboard');
      expect(dto.hasHandoff, isTrue);
    });

    test('toJson round-trips correctly', () {
      const dto = RepoSummaryDto(
        name: 'bastion',
        now: 'repo status API',
        hasHandoff: false,
      );
      final decoded = RepoSummaryDto.fromJson(dto.toJson());
      expect(decoded.name, dto.name);
      expect(decoded.now, dto.now);
      expect(decoded.hasHandoff, dto.hasHandoff);
    });

    test('missing fields fall back to empty string / false', () {
      final dto = RepoSummaryDto.fromJson(const {});
      expect(dto.name, '');
      expect(dto.now, '');
      expect(dto.hasHandoff, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // RepoStatusDto
  // -------------------------------------------------------------------------
  group('RepoStatusDto', () {
    test('fromJson decodes all fields including momentum', () {
      final dto = RepoStatusDto.fromJson({
        'name': 'bastion',
        'now': 'BA.11.D in progress — repo status API',
        'next': 'Wire WS event push',
        'blocked': '[]',
        'has_handoff': false,
        'momentum_now': 'BA.11.D in progress — repo status API',
        'momentum_next': 'Wire WS event push',
        'momentum_blocked': 'nothing blocked',
        'momentum_improve': 'tighten parser edge cases',
        'momentum_recurring': 'none yet',
      });
      expect(dto.name, 'bastion');
      expect(dto.now, 'BA.11.D in progress — repo status API');
      expect(dto.next, 'Wire WS event push');
      // The server sends the literal sentinel string "[]" for an empty YAML
      // list; the DTO layer normalises it to '' (see
      // repo_status_empty_sentinel_test.dart for full sentinel coverage).
      expect(dto.blocked, '');
      expect(dto.hasHandoff, isFalse);
      expect(dto.momentumNow, 'BA.11.D in progress — repo status API');
      expect(dto.momentumNext, 'Wire WS event push');
      expect(dto.momentumBlocked, 'nothing blocked');
      expect(dto.momentumImprove, 'tighten parser edge cases');
      expect(dto.momentumRecurring, 'none yet');
    });

    test('toJson round-trips correctly', () {
      const dto = RepoStatusDto(
        name: 'bastion-ui',
        now: 'now line',
        next: 'next line',
        blocked: 'blocked line',
        hasHandoff: true,
        momentumNow: 'm now',
        momentumNext: 'm next',
        momentumBlocked: 'm blocked',
        momentumImprove: 'm improve',
        momentumRecurring: 'm recurring',
      );
      final decoded = RepoStatusDto.fromJson(dto.toJson());
      expect(decoded.name, dto.name);
      expect(decoded.now, dto.now);
      expect(decoded.next, dto.next);
      expect(decoded.blocked, dto.blocked);
      expect(decoded.hasHandoff, dto.hasHandoff);
      expect(decoded.momentumNow, dto.momentumNow);
      expect(decoded.momentumNext, dto.momentumNext);
      expect(decoded.momentumBlocked, dto.momentumBlocked);
      expect(decoded.momentumImprove, dto.momentumImprove);
      expect(decoded.momentumRecurring, dto.momentumRecurring);
    });

    test('missing fields fall back to empty string / false', () {
      final dto = RepoStatusDto.fromJson(const {});
      expect(dto.name, '');
      expect(dto.now, '');
      expect(dto.next, '');
      expect(dto.blocked, '');
      expect(dto.hasHandoff, isFalse);
      expect(dto.momentumNow, '');
      expect(dto.momentumNext, '');
      expect(dto.momentumBlocked, '');
      expect(dto.momentumImprove, '');
      expect(dto.momentumRecurring, '');
    });
  });

  // -------------------------------------------------------------------------
  // HandoffInfo
  // -------------------------------------------------------------------------
  group('HandoffInfo', () {
    test('fromJson decodes title/body', () {
      final dto = HandoffInfo.fromJson({
        'title': 'Handoff — BA.11.C wrap-up',
        'body': '---\ntype: Handoff\n...\n# Handoff — BA.11.C wrap-up\n...',
      });
      expect(dto.title, 'Handoff — BA.11.C wrap-up');
      expect(dto.body, contains('# Handoff'));
    });

    test('toJson round-trips correctly', () {
      const dto = HandoffInfo(title: 'My Handoff', body: '# body text');
      final decoded = HandoffInfo.fromJson(dto.toJson());
      expect(decoded.title, dto.title);
      expect(decoded.body, dto.body);
    });

    test('missing fields fall back to empty string', () {
      final dto = HandoffInfo.fromJson(const {});
      expect(dto.title, '');
      expect(dto.body, '');
    });
  });

  // -------------------------------------------------------------------------
  // WorkflowStateDto
  // -------------------------------------------------------------------------
  group('WorkflowStateDto', () {
    for (final status in ['running', 'done', 'blocked']) {
      test('fromJson decodes a workflow with status "$status"', () {
        final dto = WorkflowStateDto.fromJson({
          'spec_slug': 'phase6-blockA',
          'branch': 'phase6-blockA-flow',
          'status': status,
          'current_task': 5,
          'started_at': '2026-06-25T18:30:59Z',
          'updated_at': '2026-06-25T19:02:33Z',
        });
        expect(dto.specSlug, 'phase6-blockA');
        expect(dto.branch, 'phase6-blockA-flow');
        expect(dto.status, status);
        expect(dto.currentTask, 5);
        expect(dto.startedAt, '2026-06-25T18:30:59Z');
        expect(dto.updatedAt, '2026-06-25T19:02:33Z');
      });
    }

    test('toJson round-trips correctly', () {
      const dto = WorkflowStateDto(
        specSlug: '2.A-dashboard-repo-detail',
        branch: '2.A-dashboard-repo-detail-flow',
        status: 'running',
        currentTask: 3,
        startedAt: '2026-07-02T10:00:00Z',
        updatedAt: '2026-07-02T10:15:00Z',
      );
      final decoded = WorkflowStateDto.fromJson(dto.toJson());
      expect(decoded.specSlug, dto.specSlug);
      expect(decoded.branch, dto.branch);
      expect(decoded.status, dto.status);
      expect(decoded.currentTask, dto.currentTask);
      expect(decoded.startedAt, dto.startedAt);
      expect(decoded.updatedAt, dto.updatedAt);
    });

    test('current_task decodes from a JSON integer, not string', () {
      final dto = WorkflowStateDto.fromJson(const {'current_task': 7});
      expect(dto.currentTask, 7);
      expect(dto.currentTask, isA<int>());
    });

    test('missing fields fall back to empty string / zero', () {
      final dto = WorkflowStateDto.fromJson(const {});
      expect(dto.specSlug, '');
      expect(dto.branch, '');
      expect(dto.status, '');
      expect(dto.currentTask, 0);
      expect(dto.startedAt, '');
      expect(dto.updatedAt, '');
    });
  });
}
