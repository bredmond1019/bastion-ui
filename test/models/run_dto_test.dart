import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/run_dto.dart';

import '../support/wire_fixtures.dart';

void main() {
  group('RunSummaryDto', () {
    test('fully-populated payload, including v0.22 repo', () {
      final run = RunSummaryDto.fromJson(runSummaryFullFixture);

      expect(run.runId, 'b6a1c1e0-0000-4000-8000-000000000000');
      expect(run.workflowType, isNull);
      expect(run.status, 'running');
      expect(run.specSlug, '11.T-run-summary-projection');
      expect(run.startedAt, '2026-07-24T12:00:00Z');
      expect(run.updatedAt, '2026-07-24T12:00:01Z');
      expect(run.repo, 'bastion-ui');
    });

    test(
      'minimal payload — every optional absent, including workflow_type',
      () {
        final run = RunSummaryDto.fromJson(runSummaryMinimalFixture);

        expect(run.runId, 'c7b2d2f1-0000-4000-8000-000000000000');
        expect(run.workflowType, isNull);
        expect(run.status, 'pending');
        expect(run.specSlug, isNull);
        expect(run.startedAt, isNull);
        expect(run.updatedAt, isNull);
        expect(run.repo, isNull);
      },
    );

    test('suspended status is live, not lifecycle-terminal', () {
      final run = RunSummaryDto.fromJson(runSummarySuspendedFixture);

      expect(run.status, 'suspended');
    });

    test('unrecognised status decodes without throwing', () {
      final run = RunSummaryDto.fromJson({
        'run_id': 'e0f4a4b3-0000-4000-8000-000000000000',
        'status': 'some_future_status',
      });

      expect(run.status, 'some_future_status');
    });

    test('empty collection decodes to an empty list', () {
      final runs = runsEmptyFixture
          .whereType<Map<String, dynamic>>()
          .map(RunSummaryDto.fromJson)
          .toList();

      expect(runs, isEmpty);
    });

    test('populated collection decodes every entry', () {
      final runs = runsFixture
          .whereType<Map<String, dynamic>>()
          .map(RunSummaryDto.fromJson)
          .toList();

      expect(runs, hasLength(3));
      expect(runs[2].status, 'suspended');
    });
  });

  group('RunStateDto / NodeTransitionDto / RunUsageDto', () {
    test('fully-populated payload — no aggregate status field exists', () {
      final state = RunStateDto.fromJson(runStateFullFixture);

      expect(state.runId, 'b6a1c1e0-0000-4000-8000-000000000000');
      expect(state.event, {'ticket_id': 'T-1'});
      expect(state.metadata, {'workflow': 'sdlc-flow'});
      expect(state.nodes, hasLength(2));

      final success = state.nodes[0];
      expect(success.node, 'DataIngestionNode');
      expect(success.status, 'success');
      expect(success.startedAt, '2026-07-24T12:00:00Z');
      expect(success.completedAt, '2026-07-24T12:00:01Z');
      expect(success.error, isNull);
      expect(success.input, isNull);
      expect(success.output, {'documents_loaded': 3});
      expect(success.usage, isNull);

      final failed = state.nodes[1];
      expect(failed.node, 'SummarizeNode');
      expect(failed.status, 'failed');
      expect(failed.error, 'timeout');
      expect(failed.input, {'documents': 3});
      expect(failed.output, isNull);
      expect(failed.usage, isNotNull);
      expect(failed.usage!.inputTokens, 512);
      expect(failed.usage!.outputTokens, 128);
      expect(failed.usage!.model, 'claude-sonnet-5');
    });

    test('minimal — no recorded node transitions yet', () {
      final state = RunStateDto.fromJson(runStateEmptyFixture);

      expect(state.runId, 'c7b2d2f1-0000-4000-8000-000000000000');
      expect(state.nodes, isEmpty);
    });

    test('pending node — every optional field absent', () {
      final node = NodeTransitionDto.fromJson(nodeTransitionPendingFixture);

      expect(node.node, 'PendingNode');
      expect(node.status, 'pending');
      expect(node.startedAt, isNull);
      expect(node.completedAt, isNull);
      expect(node.error, isNull);
      expect(node.input, isNull);
      expect(node.output, isNull);
      expect(node.usage, isNull);
    });

    test('unrecognised node status decodes without throwing', () {
      final node = NodeTransitionDto.fromJson({
        'node': 'FutureNode',
        'status': 'some_future_status',
      });

      expect(node.status, 'some_future_status');
    });
  });
}
