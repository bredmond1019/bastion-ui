// Widget tests for SessionCard's agent-activity chip (SessionDto.agentState).
//
// SessionCard is purely presentational — it does not read providers — so
// these tests build it directly with plain constructor arguments, mirroring
// the "distinct from the running/idle badge" contract in
// `planning/ticket-session-agent-state/tasks.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/widgets/session_card.dart';

SessionDto _session(AgentState agentState) => SessionDto(
  name: 'my-session',
  state: 'running',
  lastLine: r'$ ',
  agentState: agentState,
);

Widget _buildCard(AgentState agentState) {
  return MaterialApp(
    home: Scaffold(body: SessionCard(session: _session(agentState))),
  );
}

void main() {
  testWidgets('working renders a "working" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.working));

    expect(find.text('working'), findsOneWidget);
    expect(find.byTooltip('Agent working'), findsOneWidget);
  });

  testWidgets('idle renders an "idle" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.idle));

    expect(find.text('idle'), findsOneWidget);
    expect(find.byTooltip('Agent idle'), findsOneWidget);
  });

  testWidgets('blocked renders a "blocked" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.blocked));

    expect(find.text('blocked'), findsOneWidget);
    expect(find.byTooltip('Agent blocked'), findsOneWidget);
  });

  testWidgets('unknown renders no agent-state chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.unknown));

    expect(find.text('unknown'), findsNothing);
    expect(find.text('working'), findsNothing);
    expect(find.text('idle'), findsNothing);
    expect(find.text('blocked'), findsNothing);
    expect(find.byTooltip('Agent unknown'), findsNothing);
  });

  testWidgets(
    'the running/idle tmux dot renders independently of agent state',
    (tester) async {
      // state: running (tmux pane liveness) + agent_state: idle (agent
      // activity) must NOT collapse into one signal — both affordances
      // are present simultaneously.
      await tester.pumpWidget(_buildCard(AgentState.idle));

      expect(find.byTooltip('Running'), findsOneWidget);
      expect(find.byTooltip('Agent idle'), findsOneWidget);
    },
  );
}
