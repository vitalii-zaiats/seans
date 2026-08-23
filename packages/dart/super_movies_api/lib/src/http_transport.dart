import 'package:http/http.dart' as http;

import 'transport.dart';

/// The default network stack: `package:http`.
///
/// Pass [client] to reuse a connection pool or to wrap requests with retry,
/// caching or logging — `RetryClient` from `package:http/retry.dart` drops
/// straight in. The caller then owns it: [close] leaves a supplied client open
/// and only shuts down one this transport created.
final class HttpTransport implements Transport {
  HttpTransport({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    final outgoing = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request.body != null) {
      // `Request.body` encodes as UTF-8 unless the content-type says otherwise.
      outgoing.body = request.body!;
    }

    final streamed = await _client.send(outgoing);
    final response = await http.Response.fromStream(streamed);

    // Raw bytes rather than `response.body`: the decoding is the client's, and
    // it is always UTF-8.
    return ApiResponse.bytes(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
    );
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
