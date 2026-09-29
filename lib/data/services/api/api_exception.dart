/// Typed errors from the YXZ playback API.
library;

/// Whether local yt-dlp fallback is allowed for this failure.
enum ApiFailureKind {
  /// Transport / 5xx — safe to try local extraction.
  transport,

  /// Auth problems after refresh — usually not a silent local override.
  auth,

  /// Video restricted / unavailable — must NOT fall back locally.
  restricted,

  /// Validation / client bug.
  client,

  /// Unknown.
  other,
}

/// Exception carrying server [code] for classified fallback.
class ApiException implements Exception {
  /// Creates an API exception.
  ApiException({
    required this.code,
    required this.message,
    required this.kind,
    this.statusCode,
    this.retryable = false,
  });

  /// Machine-readable error code from the server.
  final String code;

  /// Human-readable message.
  final String message;

  /// Fallback classification.
  final ApiFailureKind kind;

  /// HTTP status when known.
  final int? statusCode;

  /// Server-indicated retryability.
  final bool retryable;

  /// True when local yt-dlp may be used.
  bool get allowsLocalFallback => kind == ApiFailureKind.transport;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Maps HTTP + body error code to [ApiFailureKind].
ApiFailureKind classifyApiFailure({
  required int? statusCode,
  required String? code,
}) {
  const Set<String> restricted = <String>{
    'EXTRACTOR_VIDEO_UNAVAILABLE',
    'EXTRACTOR_PRIVATE',
    'EXTRACTOR_GEO_BLOCKED',
    'EXTRACTOR_CHALLENGE_FAILED',
    'AUTH_REVOKED',
  };
  if (code != null && restricted.contains(code)) {
    return ApiFailureKind.restricted;
  }
  if (code == 'AUTH_INVALID' ||
      code == 'AUTH_EXPIRED' ||
      statusCode == 401) {
    return ApiFailureKind.auth;
  }
  if (statusCode == null ||
      statusCode >= 500 ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504) {
    return ApiFailureKind.transport;
  }
  if (statusCode == 400) {
    return ApiFailureKind.client;
  }
  return ApiFailureKind.other;
}
