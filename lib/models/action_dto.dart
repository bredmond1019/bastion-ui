/// Quick-action command DTOs mirroring serve-api.md (v0.4) §12.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// POST /api/actions/command → CommandRequest / CommandResponse
// ---------------------------------------------------------------------------

/// Wire values for `CommandRequest.mode` (serve-api §12.1).
enum CommandMode {
  inject('inject'),
  spawn('spawn');

  final String wireValue;

  const CommandMode(this.wireValue);
}

/// Wire values for `CommandRequest.model` (serve-api §12.1).
///
/// Only meaningful when `mode` is [CommandMode.spawn]; the server defaults to
/// `sonnet` when omitted.
enum CommandModel {
  opus('opus'),
  sonnet('sonnet');

  final String wireValue;

  const CommandModel(this.wireValue);
}

/// Request body for `POST /api/actions/command` (serve-api §12.1).
///
/// Inject:
/// ```json
/// {"mode": "inject", "session": "main", "command": "/status"}
/// ```
///
/// Spawn:
/// ```json
/// {"mode": "spawn", "name": "work", "dir": "/repo", "model": "opus", "command": "/status"}
/// ```
///
/// `dir` and `model` are omitted from the wire object entirely when null;
/// `session` is emitted only for `inject`, `name` only for `spawn`.
final class CommandRequest {
  final CommandMode mode;
  final String? session;
  final String? name;
  final String? dir;
  final CommandModel? model;
  final String command;

  const CommandRequest({
    required this.mode,
    this.session,
    this.name,
    this.dir,
    this.model,
    required this.command,
  });

  Map<String, dynamic> toJson() => {
    'mode': mode.wireValue,
    if (mode == CommandMode.inject && session != null) 'session': session,
    if (mode == CommandMode.spawn && name != null) 'name': name,
    if (dir != null) 'dir': dir,
    if (model != null) 'model': model!.wireValue,
    'command': command,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandRequest &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          session == other.session &&
          name == other.name &&
          dir == other.dir &&
          model == other.model &&
          command == other.command;

  @override
  int get hashCode => Object.hash(mode, session, name, dir, model, command);

  @override
  String toString() =>
      'CommandRequest(mode: $mode, session: $session, name: $name, '
      'dir: $dir, model: $model, command: $command)';
}

/// Response body for `POST /api/actions/command` (serve-api §12.1).
///
/// ```json
/// {"session": "work"}
/// ```
final class CommandResponse {
  final String session;

  const CommandResponse({required this.session});

  factory CommandResponse.fromJson(Map<String, dynamic> json) {
    return CommandResponse(session: json['session'] as String? ?? '');
  }

  Map<String, dynamic> toJson() => {'session': session};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandResponse &&
          runtimeType == other.runtimeType &&
          session == other.session;

  @override
  int get hashCode => session.hashCode;

  @override
  String toString() => 'CommandResponse(session: $session)';
}
