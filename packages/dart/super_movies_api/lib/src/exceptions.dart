/// Base class for every error this package surfaces.
///
/// It is `sealed`, so a `switch` over a caught [ApiException] is exhaustively
/// checked by the analyzer.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  /// Human readable description, safe to log.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server answered, with a status outside 2xx.
final class ApiHttpException extends ApiException {
  ApiHttpException({
    required this.statusCode,
    required this.uri,
    required String detail,
    this.body,
  }) : super(detail);

  final int statusCode;
  final Uri uri;

  /// Raw response body, truncated to a sane length for logging.
  final String? body;

  /// Nothing there — an unknown slug, an unknown id.
  bool get isNotFound => statusCode == 404;

  /// No usable identity. The caller has to sign in, or become a guest.
  bool get isUnauthorized => statusCode == 401;

  /// We know who you are; you still cannot have this.
  bool get isForbidden => statusCode == 403;

  /// Already taken — an email somebody else registered, an account already
  /// claimed.
  bool get isConflict => statusCode == 409;

  /// The request was refused on its contents: a bad version string, a vendor
  /// where there should be none, a field the schema would not take.
  bool get isInvalid => statusCode == 400 || statusCode == 422;

  /// The API refused the request rate. Worth waiting and trying again.
  bool get isRateLimited => statusCode == 429;

  /// Upstream's fault, and a retry may well succeed.
  bool get isServerError => statusCode >= 500;
}

/// The request never produced a response: no connectivity, DNS, TLS, timeout.
final class ApiNetworkException extends ApiException {
  ApiNetworkException(this.uri, this.cause)
    : super('Network failure for $uri: $cause');

  final Uri uri;

  /// The original error, as the transport threw it.
  final Object cause;
}

/// The response arrived but could not be read as the expected shape.
///
/// Thrown when the API changes under us: a required field disappears or changes
/// type. The [message] names the offending field.
final class ApiSerializationException extends ApiException {
  ApiSerializationException(super.message, {this.cause});

  final Object? cause;
}
