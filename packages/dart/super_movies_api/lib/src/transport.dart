import 'dart:convert';
import 'dart:typed_data';

/// A single HTTP request the client wants performed.
///
/// Deliberately minimal: this API only ever needs `GET`, `POST`, `PATCH` and
/// `DELETE` with a JSON body, so an adapter for any HTTP library is a few lines
/// long.
final class ApiRequest {
  const ApiRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });

  /// Upper-case: `GET`, `POST`, `PATCH`, `DELETE`.
  final String method;

  final Uri url;

  final Map<String, String> headers;

  /// Already-encoded request body, or `null` for a body-less request. When
  /// non-null, [headers] carries `Content-Type: application/json`.
  final String? body;

  @override
  String toString() => '$method $url';
}

/// The result of an [ApiRequest].
///
/// Construct it with [ApiResponse.bytes] when the adapter can hand over the raw
/// payload, and with [ApiResponse.text] only when it cannot.
final class ApiResponse {
  /// Wraps a raw payload. Preferred: the client decodes it as UTF-8 itself.
  const ApiResponse.bytes({
    required this.statusCode,
    required Uint8List bodyBytes,
    this.headers = const {},
  }) : _bodyBytes = bodyBytes;

  /// Wraps an already-decoded body. Only when the adapter guarantees the string
  /// was decoded as UTF-8 — Cyrillic display names come back mangled otherwise.
  ApiResponse.text({
    required this.statusCode,
    required String body,
    this.headers = const {},
  }) : _bodyBytes = Uint8List.fromList(utf8.encode(body));

  final int statusCode;
  final Map<String, String> headers;

  final Uint8List _bodyBytes;

  Uint8List get bodyBytes => _bodyBytes;

  /// The payload decoded as UTF-8, never throwing on malformed input.
  String get body => utf8.decode(_bodyBytes, allowMalformed: true);

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'ApiResponse($statusCode, ${_bodyBytes.length} bytes)';
}

/// What the client talks to instead of a concrete HTTP library.
///
/// [HttpTransport] is the one it builds when you supply nothing; writing
/// another — for `dio`, for a test double, for something that retries — means
/// implementing two methods.
///
/// Two rules an implementation has to keep. It must **not** throw on a non-2xx
/// status: return the response and let the client raise [ApiHttpException]. Any
/// other failure (socket, DNS, TLS, timeout) it should throw; the client wraps
/// it in [ApiNetworkException].
abstract interface class Transport {
  /// Performs [request] and completes with the raw response.
  Future<ApiResponse> send(ApiRequest request);

  /// Releases resources held by the underlying library, if any.
  void close();
}
