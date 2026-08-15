// Unit tests for the pure Briefing ranking functions + view model
// (`lib/state/briefing_model.dart`, BU.13.B task 1).
//
// Pure Dart — no Flutter TestWidgetsFlutterBinding needed.

import 'package:bastion_ui/models/attention_dto.dart';
import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:flutter_test/flutter_test.dart';

BoardBlockDto _gate({
  required String id,
  int? dependentCount,
  List<BlockedByDto> blockedBy = const [],
}) {
  return BoardBlockDto(
    id: id,
    title: 'Block $id',
    repo: 'bastion-ui',
    blockedBy: blockedBy.isEmpty
        ? [
            const OperatorDepDto(
              slug: 'op',
              exit: 'sign-off',
              start: '2026-08-01',
            ),
          ]
        : blockedBy,
    dependentCount: dependentCount,
  );
}

AttentionCarryoverDto _carryover({
  required String slug,
  int? ageDays,
  String lane = 'blocking',
}) {
  return AttentionCarryoverDto(
    repo: 'bastion-ui',
    slug: slug,
    kind: 'known_issue',
    text: 'text for $slug',
    ageDays: ageDays,
    thresholdDays: 10,
    lane: lane,
    clearsWhenSatisfied: false,
  );
}

SessionDto _session({
  required String name,
  String state = 'running',
  AgentState agentState = AgentState.working,
}) {
  return SessionDto(name: name, state: state, agentState: agentState);
}

void main() {
  group('rankOperatorGates', () {
    test('sorts by dependent_count descending', () {
      final ranked = rankOperatorGates([
        _gate(id: 'BA.1', dependentCount: 1),
        _gate(id: 'BA.2', dependentCount: 5),
        _gate(id: 'BA.3', dependentCount: 3),
      ]);
      expect(ranked.map((g) => g.id).toList(), ['BA.2', 'BA.3', 'BA.1']);
    });

    test('ties break on id ascending', () {
      final ranked = rankOperatorGates([
        _gate(id: 'BA.z', dependentCount: 5),
        _gate(id: 'BA.a', dependentCount: 5),
      ]);
      expect(ranked.map((g) => g.id).toList(), ['BA.a', 'BA.z']);
    });

    test('null dependent_count sorts LAST, never as 0', () {
      final ranked = rankOperatorGates([
        _gate(id: 'BA.unknown', dependentCount: null),
        _gate(id: 'BA.zero', dependentCount: 0),
        _gate(id: 'BA.one', dependentCount: 1),
      ]);
      expect(ranked.map((g) => g.id).toList(), [
        'BA.one',
        'BA.zero',
        'BA.unknown',
      ]);
    });

    test('multiple nulls tie-break by id among themselves', () {
      final ranked = rankOperatorGates([
        _gate(id: 'BA.z', dependentCount: null),
        _gate(id: 'BA.a', dependentCount: null),
      ]);
      expect(ranked.map((g) => g.id).toList(), ['BA.a', 'BA.z']);
    });

    test('excludes blocked entries with no operator/approval dependency', () {
      final ranked = rankOperatorGates([
        BoardBlockDto(
          id: 'BA.dep-only',
          title: 'Dep only',
          repo: 'bastion-ui',
          blockedBy: const [BlockDepDto(repo: 'mev', id: 'MV.1.A')],
          dependentCount: 9,
        ),
        _gate(id: 'BA.gate', dependentCount: 1),
      ]);
      expect(ranked.map((g) => g.id).toList(), ['BA.gate']);
    });

    test('approval-type dependency also counts as a gate', () {
      final ranked = rankOperatorGates([
        _gate(
          id: 'BA.approval',
          dependentCount: 2,
          blockedBy: const [
            ApprovalDepDto(slug: 'deploy', what: 'push', digest: 'abc'),
          ],
        ),
      ]);
      expect(ranked, hasLength(1));
    });
  });

  group('rankNeedsInputSessions', () {
    test('sorts by idle time descending (longest-waiting first)', () {
      final ranked = rankNeedsInputSessions([
        NeedsInputSessionEntry(
          session: _session(name: 'short'),
          idle: const Duration(minutes: 5),
        ),
        NeedsInputSessionEntry(
          session: _session(name: 'long'),
          idle: const Duration(hours: 3),
        ),
      ]);
      expect(ranked.map((e) => e.session.name).toList(), ['long', 'short']);
    });

    test('ties break on session name ascending', () {
      final ranked = rankNeedsInputSessions([
        NeedsInputSessionEntry(
          session: _session(name: 'zeta'),
          idle: const Duration(minutes: 5),
        ),
        NeedsInputSessionEntry(
          session: _session(name: 'alpha'),
          idle: const Duration(minutes: 5),
        ),
      ]);
      expect(ranked.map((e) => e.session.name).toList(), ['alpha', 'zeta']);
    });

    test('null idle (not yet tracked) sorts LAST, never as zero', () {
      final ranked = rankNeedsInputSessions([
        NeedsInputSessionEntry(
          session: _session(name: 'untracked'),
          idle: null,
        ),
        NeedsInputSessionEntry(
          session: _session(name: 'brief'),
          idle: Duration.zero,
        ),
      ]);
      expect(ranked.map((e) => e.session.name).toList(), [
        'brief',
        'untracked',
      ]);
    });
  });

  group('rankBlockedBlocks', () {
    test('sorts by age_days descending', () {
      final ranked = rankBlockedBlocks([
        _carryover(slug: 'young', ageDays: 2),
        _carryover(slug: 'old', ageDays: 30),
      ]);
      expect(ranked.map((c) => c.slug).toList(), ['old', 'young']);
    });

    test('ties break on slug ascending', () {
      final ranked = rankBlockedBlocks([
        _carryover(slug: 'zeta', ageDays: 10),
        _carryover(slug: 'alpha', ageDays: 10),
      ]);
      expect(ranked.map((c) => c.slug).toList(), ['alpha', 'zeta']);
    });

    test('null age_days (snoozed/anchor-less) sorts LAST, never as zero', () {
      final ranked = rankBlockedBlocks([
        _carryover(slug: 'snoozed', ageDays: null),
        _carryover(slug: 'fresh', ageDays: 0),
      ]);
      expect(ranked.map((c) => c.slug).toList(), ['fresh', 'snoozed']);
    });

    test('excludes non-blocking-lane carryover entries', () {
      final ranked = rankBlockedBlocks([
        _carryover(slug: 'hot-not-blocking', ageDays: 99, lane: 'hot'),
        _carryover(slug: 'blocking', ageDays: 1, lane: 'blocking'),
      ]);
      expect(ranked.map((c) => c.slug).toList(), ['blocking']);
    });
  });

  group('rankLiveRuns', () {
    test('only running, non-needs-input sessions are included', () {
      final ranked = rankLiveRuns([
        _session(name: 'running-one', state: 'running'),
        _session(
          name: 'blocked-one',
          state: 'running',
          agentState: AgentState.blocked,
        ),
        _session(name: 'idle-one', state: 'idle'),
      ]);
      expect(ranked.map((s) => s.name).toList(), ['running-one']);
    });

    test('sorted by name ascending', () {
      final ranked = rankLiveRuns([
        _session(name: 'zeta', state: 'running'),
        _session(name: 'alpha', state: 'running'),
      ]);
      expect(ranked.map((s) => s.name).toList(), ['alpha', 'zeta']);
    });
  });

  group('BriefingViewModel', () {
    final board = BoardDto(
      lanes: BoardLaneDto(
        blocked: [
          _gate(id: 'BA.gate-1', dependentCount: 3),
          _gate(id: 'BA.gate-2', dependentCount: 1),
        ],
      ),
    );
    final attention = AttentionDto(
      asOf: '2026-08-14',
      lanes: AttentionLanesDto(
        staleCarryover: [
          _carryover(slug: 'blocked-1', ageDays: 5),
          _carryover(slug: 'blocked-2', ageDays: 20),
        ],
      ),
      thresholds: const AttentionThresholdsDto(
        envDays: 14,
        deferredDays: 21,
        knownIssueDays: 10,
        constraintDays: 30,
        backlogDays: 45,
      ),
    );
    final sessions = [
      _session(name: 'running-1', state: 'running'),
      _session(
        name: 'needs-input-1',
        state: 'running',
        agentState: AgentState.blocked,
      ),
    ];

    test('sections default to loading and every derived list is empty', () {
      const vm = BriefingViewModel();
      expect(vm.board.isLoading, isTrue);
      expect(vm.attention.isLoading, isTrue);
      expect(vm.sessions.isLoading, isTrue);
      expect(vm.rankedGates, isEmpty);
      expect(vm.rankedNeedsInput, isEmpty);
      expect(vm.rankedBlockedBlocks, isEmpty);
      expect(vm.liveRuns, isEmpty);
      expect(vm.needsYouCount, 0);
      expect(vm.blockedCount, 0);
      expect(vm.runningCount, 0);
    });

    test('header counts equal the ranked lane lengths when all loaded', () {
      final vm = BriefingViewModel(
        board: BriefingSectionLoaded(board),
        attention: BriefingSectionLoaded(attention),
        sessions: BriefingSectionLoaded(sessions),
      );

      expect(
        vm.needsYouCount,
        vm.rankedGates.length + vm.rankedNeedsInput.length,
      );
      expect(vm.needsYouCount, 2 + 1);
      expect(vm.blockedCount, vm.rankedBlockedBlocks.length);
      expect(vm.blockedCount, 2);
      expect(vm.runningCount, vm.liveRuns.length);
      expect(vm.runningCount, 1);
    });

    test('an errored section degrades to empty lists, not a throw', () {
      final vm = BriefingViewModel(
        board: BriefingSectionLoaded(board),
        attention: const BriefingSectionError('attention: 500'),
        sessions: BriefingSectionLoaded(sessions),
      );

      expect(vm.attention.isError, isTrue);
      expect(vm.attention.errorOrNull, 'attention: 500');
      expect(vm.rankedBlockedBlocks, isEmpty);
      expect(vm.blockedCount, 0);
      // The other two sections are unaffected.
      expect(vm.rankedGates, isNotEmpty);
      expect(vm.liveRuns, isNotEmpty);
    });

    test('needs-input idle is threaded through from needsInputIdle map', () {
      final vm = BriefingViewModel(
        board: BriefingSectionLoaded(board),
        attention: BriefingSectionLoaded(attention),
        sessions: BriefingSectionLoaded(sessions),
        needsInputIdle: const {'needs-input-1': Duration(hours: 2)},
      );

      expect(vm.rankedNeedsInput.single.idle, const Duration(hours: 2));
    });
  });
}
