// Widget tests for SessionCard's agent-activity chip (SessionDto.agentState).
//
// SessionCard is purely presentational — it does not read providers — so
// these tests build it directly with plain constructor arguments, mirroring
// the "distinct from the running/idle badge" contract in
// `planning/ticket-session-agent-state/tasks.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/session_dto.dart';
import 'package:bastion_ui/theme/app_theme.dart';
import 'package:bastion_ui/widgets/brand/brand.dart';
import 'package:bastion_ui/widgets/session_card.dart';

SessionDto _session(AgentState agentState) => SessionDto(
  name: 'my-session',
  state: 'running',
  lastLine: r'$ ',
  agentState: agentState,
);

Widget _buildCard(AgentState agentState) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: SessionCard(session: _session(agentState))),
  );
}

void main() {
  // `StatusPill` uppercases its label internally (`BU.10.C` task 2), so the
  // rendered text is `WORKING`/`IDLE`/`BLOCKED` even though the chip's own
  // tooltip text (owned by `_AgentStateChip`, not `StatusPill`) stays
  // lowercase.
  testWidgets('working renders a "WORKING" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.working));

    expect(find.text('WORKING'), findsOneWidget);
    expect(find.byTooltip('Agent working'), findsOneWidget);
    expect(find.byType(StatusPill), findsOneWidget);
  });

  testWidgets('idle renders an "IDLE" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.idle));

    expect(find.text('IDLE'), findsOneWidget);
    expect(find.byTooltip('Agent idle'), findsOneWidget);
  });

  testWidgets('blocked renders a "BLOCKED" chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.blocked));

    expect(find.text('BLOCKED'), findsOneWidget);
    expect(find.byTooltip('Agent blocked'), findsOneWidget);
  });

  testWidgets('unknown renders no agent-state chip', (tester) async {
    await tester.pumpWidget(_buildCard(AgentState.unknown));

    expect(find.text('UNKNOWN'), findsNothing);
    expect(find.text('WORKING'), findsNothing);
    expect(find.text('IDLE'), findsNothing);
    expect(find.text('BLOCKED'), findsNothing);
    expect(find.byTooltip('Agent unknown'), findsNothing);
    expect(find.byType(StatusPill), findsNothing);
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
