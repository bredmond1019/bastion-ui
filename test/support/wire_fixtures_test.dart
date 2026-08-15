// Self-test for `wire_fixtures.dart` (BU.ticket.integration-test-tier task
// 2): every fixture must decode through its corresponding DTO without
// throwing. This is the check that catches a fixture that has drifted away
// from the Dart model layer — see `planning/ticket-integration-test-tier/
// tasks.md`.
library;

import 'package:bastion_ui/models/action_dto.dart';
import 'package:bastion_ui/models/attention_dto.dart';
import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/docs_dto.dart';
import 'package:bastion_ui/models/dto.dart';
import 'package:bastion_ui/models/repo_status_dto.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wire_fixtures.dart';

List<Map<String, dynamic>> _maps(List<dynamic> raw) =>
    raw.cast<Map<String, dynamic>>();

void main() {
  group('health fixtures', () {
    test('healthFixture decodes to HealthDto', () {
      final dto = HealthDto.fromJson(healthFixture);
      expect(dto.status, 'ok');
      expect(dto.service, 'bastion');
    });
  });

  group('error fixtures', () {
    test('unauthorizedErrorFixture decodes to ErrorPayload', () {
      final dto = ErrorPayload.fromJson(unauthorizedErrorFixture);
      expect(dto.code, 'unauthorized');
    });

    test('notFoundErrorFixture decodes to ErrorPayload', () {
      final dto = ErrorPayload.fromJson(notFoundErrorFixture);
      expect(dto.code, 'C002');
    });
  });

  group('session fixtures', () {
    test('sessionFullFixture decodes to SessionDto', () {
      final dto = SessionDto.fromJson(sessionFullFixture);
      expect(dto.name, 'main');
      expect(dto.agentState, AgentState.blocked);
    });

    test('sessionMinimalFixture decodes to SessionDto', () {
      final dto = SessionDto.fromJson(sessionMinimalFixture);
      expect(dto.name, 'idle-session');
      expect(dto.lastLine, isNull);
      expect(dto.agentState, AgentState.unknown);
    });

    test('sessionsEmptyFixture decodes to an empty list', () {
      final list = _maps(
        sessionsEmptyFixture,
      ).map(SessionDto.fromJson).toList();
      expect(list, isEmpty);
    });

    test('sessionsFixture decodes to a populated list', () {
      final list = _maps(sessionsFixture).map(SessionDto.fromJson).toList();
      expect(list, hasLength(2));
    });
  });

  group('pane fixtures', () {
    test('paneFullFixture decodes to PaneDto', () {
      final dto = PaneDto.fromJson(paneFullFixture);
      expect(dto.sessionName, 'main');
      expect(dto.lines, hasLength(3));
    });

    test('paneEmptyFixture decodes to PaneDto with no lines', () {
      final dto = PaneDto.fromJson(paneEmptyFixture);
      expect(dto.lines, isEmpty);
    });
  });

  group('repo summary fixtures', () {
    test('repoSummaryFullFixture decodes to RepoSummaryDto', () {
      final dto = RepoSummaryDto.fromJson(repoSummaryFullFixture);
      expect(dto.name, 'bastion-ui');
      expect(dto.hasHandoff, isTrue);
    });

    test(
      'repoSummaryMinimalFixture decodes to RepoSummaryDto with sentinel blanked',
      () {
        final dto = RepoSummaryDto.fromJson(repoSummaryMinimalFixture);
        expect(dto.now, '');
      },
    );

    test('reposEmptyFixture decodes to an empty list', () {
      final list = _maps(
        reposEmptyFixture,
      ).map(RepoSummaryDto.fromJson).toList();
      expect(list, isEmpty);
    });

    test('reposFixture decodes to a populated list', () {
      final list = _maps(reposFixture).map(RepoSummaryDto.fromJson).toList();
      expect(list, hasLength(2));
    });
  });

  group('repo status fixtures', () {
    test('repoStatusFullFixture decodes to RepoStatusDto', () {
      final dto = RepoStatusDto.fromJson(repoStatusFullFixture);
      expect(dto.name, 'bastion-ui');
      expect(dto.momentumImprove, 'tighten fixtures');
    });

    test(
      'repoStatusMinimalFixture decodes to RepoStatusDto with sentinels blanked',
      () {
        final dto = RepoStatusDto.fromJson(repoStatusMinimalFixture);
        expect(dto.now, '');
        expect(dto.next, '');
        expect(dto.blocked, '');
      },
    );
  });

  group('handoff fixtures', () {
    test('handoffFullFixture decodes to HandoffInfo', () {
      final dto = HandoffInfo.fromJson(handoffFullFixture);
      expect(dto.title, contains('Handoff'));
    });
  });

  group('workflow fixtures', () {
    test('workflowFullFixture decodes to WorkflowStateDto', () {
      final dto = WorkflowStateDto.fromJson(workflowFullFixture);
      expect(dto.currentTask, 5);
    });

    test('workflowsEmptyFixture decodes to an empty list', () {
      final list = _maps(
        workflowsEmptyFixture,
      ).map(WorkflowStateDto.fromJson).toList();
      expect(list, isEmpty);
    });

    test('workflowsFixture decodes to a populated list', () {
      final list = _maps(
        workflowsFixture,
      ).map(WorkflowStateDto.fromJson).toList();
      expect(list, hasLength(1));
    });
  });

  group('command fixtures', () {
    test('commandInjectRequestFixture round-trips through CommandRequest', () {
      final request = CommandRequest(
        mode: CommandMode.inject,
        session: commandInjectRequestFixture['session'] as String,
        command: commandInjectRequestFixture['command'] as String,
      );
      expect(request.toJson(), commandInjectRequestFixture);
    });

    test('commandSpawnRequestFixture round-trips through CommandRequest', () {
      final request = CommandRequest(
        mode: CommandMode.spawn,
        name: commandSpawnRequestFixture['name'] as String,
        dir: commandSpawnRequestFixture['dir'] as String,
        model: CommandModel.opus,
        command: commandSpawnRequestFixture['command'] as String,
      );
      expect(request.toJson(), commandSpawnRequestFixture);
    });

    test('commandResponseFixture decodes to CommandResponse', () {
      final dto = CommandResponse.fromJson(commandResponseFixture);
      expect(dto.session, 'work');
    });
  });

  group('board fixtures', () {
    test('boardBlockFullFixture decodes to BoardBlockDto', () {
      final dto = BoardBlockDto.fromJson(boardBlockFullFixture);
      expect(dto.id, 'BA.11.K');
      expect(dto.blockedBy, hasLength(5));
      expect(dto.blockedBy[0], isA<BlockDepDto>());
      expect(dto.blockedBy[1], isA<ExternalDepDto>());
      expect(dto.blockedBy[2], isA<OperatorDepDto>());
      expect(dto.blockedBy[3], isA<ApprovalDepDto>());
      expect(dto.blockedBy[4], isA<UnknownBlockedByDto>());
      expect(dto.dependentCount, 2);
      expect(dto.ready, isTrue);
      expect(dto.unmetCount, 0);
    });

    test('boardBlockMinimalFixture decodes to BoardBlockDto', () {
      final dto = BoardBlockDto.fromJson(boardBlockMinimalFixture);
      expect(dto.blockedBy, isEmpty);
      expect(dto.dependentCount, isNull);
      expect(dto.ready, isNull);
    });

    test('boardHqFixture decodes to BoardDto', () {
      final dto = BoardDto.fromJson(boardHqFixture);
      expect(dto.scope, 'hq');
      expect(dto.lanes.now, hasLength(1));
      expect(dto.repos, isEmpty);
    });

    test('boardProjectFixture decodes to BoardDto with repos[]', () {
      final dto = BoardDto.fromJson(boardProjectFixture);
      expect(dto.repos, hasLength(1));
      expect(dto.repos.single.repo, 'bastion-ui');
      expect(dto.stale, isTrue);
    });

    test('boardEmptyFixture decodes to an empty BoardDto', () {
      final dto = BoardDto.fromJson(boardEmptyFixture);
      expect(dto.lanes.now, isEmpty);
      expect(dto.repos, isEmpty);
    });
  });

  group('attention fixtures', () {
    test('attentionCarryoverFullFixture decodes to AttentionCarryoverDto', () {
      final dto = AttentionCarryoverDto.fromJson(attentionCarryoverFullFixture);
      expect(dto.ageDays, 13);
      expect(dto.unmetBlocks, ['BU.ticket.other']);
    });

    test('attentionCarryoverMinimalFixture decodes with null ageDays', () {
      final dto = AttentionCarryoverDto.fromJson(
        attentionCarryoverMinimalFixture,
      );
      expect(dto.ageDays, isNull);
    });

    test('attentionBacklogFullFixture decodes to AttentionBacklogDto', () {
      final dto = AttentionBacklogDto.fromJson(attentionBacklogFullFixture);
      expect(dto.ageDays, 60);
    });

    test('attentionBacklogMinimalFixture decodes to AttentionBacklogDto', () {
      final dto = AttentionBacklogDto.fromJson(attentionBacklogMinimalFixture);
      expect(dto.notes, isNull);
    });

    test('attentionThresholdsFixture decodes to AttentionThresholdsDto', () {
      final dto = AttentionThresholdsDto.fromJson(attentionThresholdsFixture);
      expect(dto.envDays, 14);
    });

    test('attentionFixture decodes to a populated AttentionDto', () {
      final dto = AttentionDto.fromJson(attentionFixture);
      expect(dto.lanes.staleCarryover, hasLength(2));
      expect(dto.lanes.agingBacklog, hasLength(1));
      expect(dto.lanes.orphanedCaptures, hasLength(1));
    });

    test('attentionEmptyFixture decodes to an empty AttentionDto', () {
      final dto = AttentionDto.fromJson(attentionEmptyFixture);
      expect(dto.lanes.staleCarryover, isEmpty);
      expect(dto.lanes.agingBacklog, isEmpty);
      expect(dto.lanes.orphanedCaptures, isEmpty);
    });
  });

  group('docs fixtures', () {
    test('docTreeFullFixture decodes to DocTreeDto', () {
      final dto = DocTreeDto.fromJson(docTreeFullFixture);
      expect(dto.entries, hasLength(2));
      expect(dto.entries[0].isDir, isTrue);
      expect(dto.entries[1].isDir, isFalse);
    });

    test('docTreeEmptyFixture decodes to DocTreeDto with no entries', () {
      final dto = DocTreeDto.fromJson(docTreeEmptyFixture);
      expect(dto.entries, isEmpty);
    });

    test('docFileFullFixture decodes to DocFileDto', () {
      final dto = DocFileDto.fromJson(docFileFullFixture);
      expect(dto.modified, isNotNull);
      expect(dto.bytes, 20);
    });

    test(
      'docFileMinimalFixture decodes to DocFileDto with modified absent',
      () {
        final dto = DocFileDto.fromJson(docFileMinimalFixture);
        expect(dto.modified, isNull);
        expect(dto.content, '');
      },
    );
  });
}
