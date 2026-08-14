/// Session + pane DTOs mirroring serve-api.md (v0.1) §10.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// GET /api/sessions → SessionDto[]
// ---------------------------------------------------------------------------

/// Detected agent activity for a session (serve-api v0.26 §10.3).
///
/// This is DISTINCT from [SessionDto.state], which is tmux **pane
/// liveness**. `agentState` is detected **agent** activity — a session can
/// be `state: "running"` (pane alive) while `agentState` is
/// [AgentState.idle] (the agent inside it isn't doing anything). Never
/// collapse the two.
enum AgentState {
  idle,
  working,
  blocked,
  unknown;

  /// Maps the exact wire strings `"idle"` / `"working"` / `"blocked"` /
  /// `"unknown"` to their enum value. An absent key (older server that
  /// predates v0.26) or any unrecognised value degrades to [unknown]
  /// rather than throwing.
  factory AgentState.fromWire(String? value) {
    switch (value) {
      case 'idle':
        return AgentState.idle;
      case 'working':
        return AgentState.working;
      case 'blocked':
        return AgentState.blocked;
      default:
        return AgentState.unknown;
    }
  }

  /// The wire string for this value (Standing Rule 6 — mirror the
  /// contract, never redefine it: the wire type stays a `String`).
  String toWire() => name;
}

/// A single tmux-backed session summary (serve-api §10).
///
/// ```json
/// {"name": "my-session", "state": "running", "last_line": "$ ", "agent_state": "working"}
/// ```
///
/// `agent_state` arrives on BOTH `GET /api/sessions` and the `sessions`
/// WebSocket push (serve-api v0.26 §10.3), so [agentState] stays live
/// without extra work. It is DISTINCT from [state], which is tmux pane
/// liveness — see [AgentState] doc comment.
final class SessionDto {
  final String name;
  final String state;
  final String? lastLine;
  final AgentState agentState;

  const SessionDto({
    required this.name,
    required this.state,
    this.lastLine,
    this.agentState = AgentState.unknown,
  });

  factory SessionDto.fromJson(Map<String, dynamic> json) {
    return SessionDto(
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? '',
      lastLine: json['last_line'] as String?,
      agentState: AgentState.fromWire(json['agent_state'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'state': state,
    if (lastLine != null) 'last_line': lastLine,
    'agent_state': agentState.toWire(),
  };
}

// ---------------------------------------------------------------------------
// GET /api/sessions/{name}/pane?lines=N → PaneDto
// ---------------------------------------------------------------------------

/// A snapshot of a session's pane text (serve-api §10).
///
/// ```json
/// {"session_name": "my-session", "lines": ["$ ls", "foo.txt"]}
/// ```
final class PaneDto {
  final String sessionName;
  final List<String> lines;

  const PaneDto({required this.sessionName, required this.lines});

  factory PaneDto.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    return PaneDto(
      sessionName: json['session_name'] as String? ?? '',
      lines: rawLines is List
          ? rawLines.map((e) => e.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'session_name': sessionName,
    'lines': lines,
  };
}
