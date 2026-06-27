/// v0 DTOs mirroring serve-api.md (v0.1) §2 and §4.
///
/// Expanded per later phases as new REST surfaces are added.
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// GET /health → HealthDto
// ---------------------------------------------------------------------------

/// Response shape for `GET /health` (serve-api §4).
///
/// ```json
/// {"status": "ok", "service": "bastion"}
/// ```
final class HealthDto {
  final String status;
  final String service;

  const HealthDto({required this.status, required this.service});

  factory HealthDto.fromJson(Map<String, dynamic> json) {
    return HealthDto(
      status: json['status'] as String? ?? '',
      service: json['service'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'status': status, 'service': service};
}

// ---------------------------------------------------------------------------
// Auth / error shapes (§2.2 and §5)
// ---------------------------------------------------------------------------

/// REST-level error payload returned on `401` and other error responses.
///
/// ```json
/// {"error": "unauthorized", "code": "unauthorized"}
/// ```
///
/// `error` and `message` are optional — only `code` is guaranteed on 401.
final class ErrorPayload {
  /// Top-level error label (e.g. `"unauthorized"`). May be absent on
  /// non-auth errors; inspect [code] for the canonical discriminator.
  final String? error;

  /// Machine-readable error code (always present on 401).
  final String code;

  /// Human-readable description (optional).
  final String? message;

  const ErrorPayload({this.error, required this.code, this.message});

  factory ErrorPayload.fromJson(Map<String, dynamic> json) {
    return ErrorPayload(
      error: json['error'] as String?,
      code: json['code'] as String? ?? 'unknown',
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (error != null) 'error': error,
    'code': code,
    if (message != null) 'message': message,
  };
}
