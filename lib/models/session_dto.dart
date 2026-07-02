/// Session + pane DTOs mirroring serve-api.md (v0.1) §10.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// GET /api/sessions → SessionDto[]
// ---------------------------------------------------------------------------

/// A single tmux-backed session summary (serve-api §10).
///
/// ```json
/// {"name": "my-session", "state": "running", "last_line": "$ "}
/// ```
final class SessionDto {
  final String name;
  final String state;
  final String? lastLine;

  const SessionDto({required this.name, required this.state, this.lastLine});

  factory SessionDto.fromJson(Map<String, dynamic> json) {
    return SessionDto(
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? '',
      lastLine: json['last_line'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'state': state,
    if (lastLine != null) 'last_line': lastLine,
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
