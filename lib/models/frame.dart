/// WS frame envelope mirroring serve-api.md §5 (v0).
///
/// The envelope is `{"kind": "<snake_case>", "payload": <any JSON>}`.
/// Known v0 kinds: `echo` and `error`. Unknown kinds are represented
/// by [UnknownFrame] so a v0.1+ server frame never crashes the client.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

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
