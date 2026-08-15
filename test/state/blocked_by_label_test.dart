import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/state/blocked_by_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('blockedByLabel', () {
    test('BlockDepDto with what includes repo, id, and what', () {
      final label = blockedByLabel(
        const BlockDepDto(repo: 'bastion', id: 'BA.11.K', what: 'schema'),
      );
      expect(label, contains('bastion/BA.11.K'));
      expect(label, contains('schema'));
    });

    test('BlockDepDto without what includes repo and id only', () {
      final label = blockedByLabel(
        const BlockDepDto(repo: 'bastion', id: 'BA.11.K'),
      );
      expect(label, contains('bastion/BA.11.K'));
      expect(label, isNotEmpty);
    });

    test('ExternalDepDto renders its what', () {
      final label = blockedByLabel(
        const ExternalDepDto(what: 'Tailscale ACL change'),
      );
      expect(label, contains('Tailscale ACL change'));
    });

    test('OperatorDepDto with what includes slug, start, exit, and what', () {
      final label = blockedByLabel(
        const OperatorDepDto(
          slug: 'ops-session-1',
          exit: 'decision-made',
          start: 'operator-review',
          what: 'credential rotation',
        ),
      );
      expect(label, contains('ops-session-1'));
      expect(label, contains('operator-review'));
      expect(label, contains('decision-made'));
      expect(label, contains('credential rotation'));
    });

    test('OperatorDepDto without what omits the trailing clause', () {
      final label = blockedByLabel(
        const OperatorDepDto(
          slug: 'ops-session-1',
          exit: 'decision-made',
          start: 'operator-review',
        ),
      );
      expect(label, contains('ops-session-1'));
      expect(label, isNotEmpty);
    });

    test('ApprovalDepDto includes slug, what, and digest', () {
      final label = blockedByLabel(
        const ApprovalDepDto(
          slug: 'approve-deploy',
          what: 'production release',
          digest: 'abc123',
        ),
      );
      expect(label, contains('approve-deploy'));
      expect(label, contains('production release'));
      expect(label, contains('abc123'));
    });

    test('UnknownBlockedByDto with a type names the raw type', () {
      final label = blockedByLabel(
        const UnknownBlockedByDto(raw: {'type': 'mystery'}),
      );
      expect(label, isNotEmpty);
      expect(label, contains('mystery'));
    });

    test('UnknownBlockedByDto with an unexpected shape degrades honestly', () {
      // No `type` key at all — an even less-recognisable shape than a
      // known-but-unhandled type string.
      final label = blockedByLabel(
        const UnknownBlockedByDto(raw: {'foo': 'bar', 'baz': 42}),
      );
      expect(label, isNotEmpty);
      expect(label, isNot(equals('')));
    });

    test('UnknownBlockedByDto never renders an empty string', () {
      final label = blockedByLabel(const UnknownBlockedByDto(raw: {}));
      expect(label.trim(), isNotEmpty);
    });
  });
}
