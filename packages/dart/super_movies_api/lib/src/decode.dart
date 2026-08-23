import 'dart:convert';

import 'exceptions.dart';
import 'json.dart';
import 'transport.dart';

/// Enough of a failing body to tell what happened, without filling a log line.
const int bodyClip = 512;

/// Turns a response into a JSON object, or into the right exception.
///
/// Shared rather than private because more than one package in this repo talks
/// to this API, and two copies of "what a refusal looks like" is how they end up
/// disagreeing about which field carries the message.
JsonMap decodeObject(ApiResponse response, Uri uri) {
  // Always UTF-8, whatever the adapter saw: the API answers `application/json`
  // with no charset, and a latin-1 guess mangles every Cyrillic display name.
  final text = response.body;

  if (!response.isSuccess) {
    throw ApiHttpException(
      statusCode: response.statusCode,
      uri: uri,
      detail: detailOf(text, response.statusCode),
      body: text.length > bodyClip ? '${text.substring(0, bodyClip)}…' : text,
    );
  }

  // 204, and any other body-less success. Nothing to read, nothing wrong.
  if (text.trim().isEmpty) return const {};

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (error) {
    throw ApiSerializationException(
      'response from $uri is not valid JSON',
      cause: error,
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw ApiSerializationException(
      'expected a JSON object from $uri, got ${decoded.runtimeType}',
    );
  }
  return decoded;
}

/// The message worth showing.
///
/// The API answers a refusal with `{"detail": "..."}`; a schema rejection
/// answers with a list of them, and the first one is the only one anybody reads.
String detailOf(String body, int statusCode) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          final where = first['loc'] is List
              ? (first['loc'] as List).join('.')
              : null;
          return where == null
              ? '${first['msg']}'
              : '${first['msg']} at $where';
        }
      }
    }
  } on FormatException {
    // Not JSON. Fall through to the generic message.
  }
  return 'HTTP $statusCode';
}
