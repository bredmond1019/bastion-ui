import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/repo_status_dto.dart';

void main() {
  // -------------------------------------------------------------------------
  // RepoSummaryDto.now
  // -------------------------------------------------------------------------
  group('RepoSummaryDto empty-sentinel normalisation', () {
    test('"[]" normalises to empty', () {
      final dto = RepoSummaryDto.fromJson({'name': 'bastion-ui', 'now': '[]'});
      expect(dto.now, '');
    });

    test('"{}" normalises to empty', () {
      final dto = RepoSummaryDto.fromJson({'name': 'bastion-ui', 'now': '{}'});
      expect(dto.now, '');
    });

    test('"[ ]" normalises to empty', () {
      final dto = RepoSummaryDto.fromJson({'name': 'bastion-ui', 'now': '[ ]'});
      expect(dto.now, '');
    });

    test('"" stays empty', () {
      final dto = RepoSummaryDto.fromJson({'name': 'bastion-ui', 'now': ''});
      expect(dto.now, '');
    });

    test('absent key stays empty', () {
      final dto = RepoSummaryDto.fromJson({'name': 'bastion-ui'});
      expect(dto.now, '');
    });

    test('a normal value passes through unchanged', () {
      final dto = RepoSummaryDto.fromJson({
        'name': 'bastion-ui',
        'now': 'wiring dashboard',
      });
      expect(dto.now, 'wiring dashboard');
    });

    test('a real value containing brackets is not blanked', () {
      final dto = RepoSummaryDto.fromJson({
        'name': 'bastion-ui',
        'now': 'fixing parse of [] literals',
      });
      expect(dto.now, 'fixing parse of [] literals');
    });
  });

  // -------------------------------------------------------------------------
  // RepoStatusDto — now/next/blocked + all five momentum_* fields
  // -------------------------------------------------------------------------
  group('RepoStatusDto empty-sentinel normalisation', () {
    const sentinelJson = {
      'name': 'bastion-ui',
      'now': '[]',
      'next': '{}',
      'blocked': '[ ]',
      'has_handoff': false,
      'momentum_now': '[]',
      'momentum_next': '{}',
      'momentum_blocked': '[ ]',
      'momentum_improve': '{ }',
      'momentum_recurring': '[]',
    };

    test('"[]", "{}", "[ ]", "{ }" all normalise to empty', () {
      final dto = RepoStatusDto.fromJson(sentinelJson);
      expect(dto.now, '');
      expect(dto.next, '');
      expect(dto.blocked, '');
      expect(dto.momentumNow, '');
      expect(dto.momentumNext, '');
      expect(dto.momentumBlocked, '');
      expect(dto.momentumImprove, '');
      expect(dto.momentumRecurring, '');
    });

    test('"" stays empty', () {
      final dto = RepoStatusDto.fromJson({'name': 'bastion-ui', 'now': ''});
      expect(dto.now, '');
    });

    test('absent key stays empty', () {
      final dto = RepoStatusDto.fromJson({'name': 'bastion-ui'});
      expect(dto.now, '');
      expect(dto.next, '');
      expect(dto.blocked, '');
      expect(dto.momentumNow, '');
      expect(dto.momentumNext, '');
      expect(dto.momentumBlocked, '');
      expect(dto.momentumImprove, '');
      expect(dto.momentumRecurring, '');
    });

    test('a normal value passes through unchanged', () {
      final dto = RepoStatusDto.fromJson({
        'name': 'bastion-ui',
        'now': 'wiring dashboard',
        'next': 'repo detail',
        'momentum_now': 'shipping steadily',
      });
      expect(dto.now, 'wiring dashboard');
      expect(dto.next, 'repo detail');
      expect(dto.momentumNow, 'shipping steadily');
    });

    test('a real value containing brackets is not blanked', () {
      final dto = RepoStatusDto.fromJson({
        'name': 'bastion-ui',
        'now': 'fixing parse of [] literals',
      });
      expect(dto.now, 'fixing parse of [] literals');
    });
  });
}
