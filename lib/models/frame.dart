/// WS frame envelope mirroring serve-api.md §5 (v0) and §7-9 (v0.2 WS-hub).
///
/// The envelope is `{"kind": "<snake_case>", "payload": <any JSON>}`.
/// Known v0 kinds: `echo` and `error`. Known v0.2 server->client kinds:
/// `sessions`, `pane`, `event`. Unknown kinds are represented by
/// [UnknownFrame] so a v0.1+ server frame never crashes the client.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

import 'session_dto.dart';

// ---------------------------------------------------------------------------
// Frame envelope
// ---------------------------------------------------------------------------

/// A decoded WebSocket frame from `bastion serve`.
sealed class BastionFrame {
  /// The raw `kind` string from the wire.
  String get kind;

  const BastionFrame();

  /// Decode a JSON map into the appropriate [BastionFrame] subtype.
  ///
  /// Never throws for unknown `kind` values — returns [UnknownFrame].
  /// Returns [MalformedFrame] when required fields are absent or the
  /// input itself is not a JSON object.
  factory BastionFrame.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'];
    if (rawKind is! String) {
      return MalformedFrame(
        raw: json,
        reason: 'missing or non-string "kind" field',
      );
    }
    final payload = json['payload'];
    switch (rawKind) {
      case 'echo':
        return EchoFrame(payload: payload);
      case 'error':
        if (payload is Map<String, dynamic>) {
          return ErrorFrame(payload: ErrorPayloadFrame.fromJson(payload));
        }
        return MalformedFrame(
          raw: json,
          reason: '"error" frame payload is not a JSON object',
        );
      case 'sessions':
        if (payload is Map<String, dynamic>) {
          final rawSessions = payload['sessions'];
          if (rawSessions is List) {
            return SessionsFrame(
              sessions: rawSessions
                  .whereType<Map<String, dynamic>>()
                  .map(SessionDto.fromJson)
                  .toList(),
            );
          }
        }
        return MalformedFrame(
          raw: json,
          reason: '"sessions" frame payload is missing "sessions" list',
        );
      case 'pane':
        if (payload is Map<String, dynamic>) {
          final session = payload['session'];
          final seq = payload['seq'];
          final rawLines = payload['lines'];
          if (session is String && seq is num && rawLines is List) {
            return PaneFrame(
              session: session,
              seq: seq.toInt(),
              lines: rawLines.map((e) => e.toString()).toList(),
            );
          }
        }
        return MalformedFrame(
          raw: json,
          reason: '"pane" frame payload missing "session"/"seq"/"lines"',
        );
      case 'event':
        if (payload is Map<String, dynamic>) {
          final session = payload['session'];
          final event = payload['event'];
          if (session is String && event is String) {
            return EventFrame(session: session, event: event, extra: payload);
          }
        }
        return MalformedFrame(
          raw: json,
          reason: '"event" frame payload missing "session"/"event"',
        );
      default:
        return UnknownFrame(kind: rawKind, payload: payload);
    }
  }

  /// Encode this frame as a JSON map suitable for `jsonEncode`.
  Map<String, dynamic> toJson();
}

// ---------------------------------------------------------------------------
// v0 known kinds
// ---------------------------------------------------------------------------

/// `echo` — server reflects the sent payload back verbatim.
final class EchoFrame extends BastionFrame {
  @override
  String get kind => 'echo';

  /// Arbitrary JSON payload (reflected from the client).
  final Object? payload;

  const EchoFrame({required this.payload});

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'payload': payload};
}

/// `error` — server-sent error with a typed payload.
final class ErrorFrame extends BastionFrame {
  @override
  String get kind => 'error';

  final ErrorPayloadFrame payload;

  const ErrorFrame({required this.payload});

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'payload': payload.toJson()};
}

// ---------------------------------------------------------------------------
// v0.2 WS-hub server->client kinds
// ---------------------------------------------------------------------------

/// `sessions` — full snapshot of live sessions, pushed on topic `"sessions"`.
final class SessionsFrame extends BastionFrame {
  @override
  String get kind => 'sessions';

  final List<SessionDto> sessions;

  const SessionsFrame({required this.sessions});

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'payload': {'sessions': sessions.map((s) => s.toJson()).toList()},
  };
}

/// `pane` — an incremental pane update, pushed on topic `"pane:<name>"`.
final class PaneFrame extends BastionFrame {
  @override
  String get kind => 'pane';

  final String session;
  final int seq;
  final List<String> lines;

  const PaneFrame({
    required this.session,
    required this.seq,
    required this.lines,
  });

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'payload': {'session': session, 'seq': seq, 'lines': lines},
  };
}

/// `event` — a session lifecycle event (e.g. `needs_input`).
///
/// [extra] is the raw JSON payload map (including `session`/`event`) so
/// future event fields never break decoding.
final class EventFrame extends BastionFrame {
  @override
  String get kind => 'event';

  final String session;
  final String event;
  final Map<String, dynamic> extra;

  const EventFrame({
    required this.session,
    required this.event,
    required this.extra,
  });

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'payload': extra};
}

// ---------------------------------------------------------------------------
// v0.2 WS-hub client->server encoders
// ---------------------------------------------------------------------------

/// Client->server frame encoders. These are plain functions (not
/// [BastionFrame] subtypes, since the client never needs to decode its own
/// outbound frames) that produce the wire JSON map for `jsonEncode`.
class ClientFrames {
  const ClientFrames._();

  /// `subscribe {topic}` — subscribe to `"sessions"` or `"pane:<name>"`.
  static Map<String, dynamic> subscribe(String topic) => {
    'kind': 'subscribe',
    'payload': {'topic': topic},
  };

  /// `unsubscribe {topic}`.
  static Map<String, dynamic> unsubscribe(String topic) => {
    'kind': 'unsubscribe',
    'payload': {'topic': topic},
  };

  /// `send {session, keys}` — send a literal key sequence to a session.
  static Map<String, dynamic> send({
    required String session,
    required String keys,
  }) => {
    'kind': 'send',
    'payload': {'session': session, 'keys': keys},
  };

  /// `send_key {session, key}` — send a single named key to a session.
  static Map<String, dynamic> sendKey({
    required String session,
    required String key,
  }) => {
    'kind': 'send_key',
    'payload': {'session': session, 'key': key},
  };
}

// ---------------------------------------------------------------------------
// Passthrough / degraded variants
// ---------------------------------------------------------------------------

/// An unrecognised `kind` — preserved verbatim so the client stays
/// forward-compatible with v0.1+ server kinds.
final class UnknownFrame extends BastionFrame {
  @override
  final String kind;

  final Object? payload;

  const UnknownFrame({required this.kind, required this.payload});

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'payload': payload};
}

/// A frame that could not be decoded (missing `kind`, wrong payload shape,
/// etc.). Carries the raw map and a human-readable reason.
final class MalformedFrame extends BastionFrame {
  @override
  String get kind => '__malformed__';

  final Map<String, dynamic> raw;
  final String reason;

  const MalformedFrame({required this.raw, required this.reason});

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'raw': raw, 'reason': reason};
}

// ---------------------------------------------------------------------------
// Error payload shape (reused in ErrorFrame)
// ---------------------------------------------------------------------------

/// Payload of an `error` frame: `{"code": "<string>", "message": "<string?>"}`.
final class ErrorPayloadFrame {
  final String code;
  final String? message;

  const ErrorPayloadFrame({required this.code, this.message});

  factory ErrorPayloadFrame.fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! String) {
      return const ErrorPayloadFrame(
        code: 'unknown',
        message: 'malformed error payload — missing "code"',
      );
    }
    return ErrorPayloadFrame(code: code, message: json['message'] as String?);
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    if (message != null) 'message': message,
  };
}
