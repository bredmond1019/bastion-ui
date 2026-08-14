import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';

void main() {
  group('AgentState.fromWire', () {
    test('maps "idle" to AgentState.idle', () {
      expect(AgentState.fromWire('idle'), AgentState.idle);
    });

    test('maps "working" to AgentState.working', () {
      expect(AgentState.fromWire('working'), AgentState.working);
    });

    test('maps "blocked" to AgentState.blocked', () {
      expect(AgentState.fromWire('blocked'), AgentState.blocked);
    });

    test('maps "unknown" to AgentState.unknown', () {
      expect(AgentState.fromWire('unknown'), AgentState.unknown);
    });

    test('maps an absent (null) value to AgentState.unknown', () {
      expect(AgentState.fromWire(null), AgentState.unknown);
    });

    test('maps an unrecognised value to AgentState.unknown, not a throw', () {
      expect(AgentState.fromWire('garbage'), AgentState.unknown);
    });
  });

  group('SessionDto.agentState', () {
    test('parses agent_state from JSON for each contract value', () {
      for (final value in ['idle', 'working', 'blocked', 'unknown']) {
        final dto = SessionDto.fromJson({
          'name': 'main',
          'state': 'running',
          'agent_state': value,
        });
        expect(dto.agentState, AgentState.fromWire(value));
      }
    });

    test('defaults to AgentState.unknown when agent_state key is absent', () {
      final dto = SessionDto.fromJson({'name': 'main', 'state': 'running'});
      expect(dto.agentState, AgentState.unknown);
    });

    test(
      'defaults to AgentState.unknown for an unrecognised agent_state value',
      () {
        final dto = SessionDto.fromJson({
          'name': 'main',
          'state': 'running',
          'agent_state': 'garbage',
        });
        expect(dto.agentState, AgentState.unknown);
      },
    );

    test('toJson() emits the wire string for agentState', () {
      const dto = SessionDto(
        name: 'main',
        state: 'running',
        agentState: AgentState.working,
      );
      expect(dto.toJson()['agent_state'], 'working');
    });

    test('toJson() round-trips the default unknown value', () {
      const dto = SessionDto(name: 'main', state: 'running');
      expect(dto.toJson()['agent_state'], 'unknown');
    });
  });
}
