import 'dart:convert';
import 'dart:typed_data';

import 'package:super_movies_api/super_movies_api.dart';

/// A [Transport] that answers from memory and records what it was asked for.
final class FakeTransport implements Transport {
  FakeTransport(this._handler);

  /// Always answers with [body], encoded as UTF-8.
  factory FakeTransport.json(Object body, {int statusCode = 200}) =>
      FakeTransport(
        (_) async => ApiResponse.bytes(
          statusCode: statusCode,
          bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
        ),
      );

  /// Answers with a body-less success, the way `204 No Content` does.
  factory FakeTransport.empty({int statusCode = 204}) => FakeTransport(
    (_) async =>
        ApiResponse.bytes(statusCode: statusCode, bodyBytes: Uint8List(0)),
  );

  /// Always fails the way a dead network would.
  factory FakeTransport.failing(Object error) =>
      FakeTransport((_) async => throw error);

  final Future<ApiResponse> Function(ApiRequest request) _handler;

  /// Every request that reached the transport, in order.
  final List<ApiRequest> requests = [];

  bool closed = false;

  ApiRequest get lastRequest => requests.last;

  Map<String, dynamic> get lastBody =>
      jsonDecode(lastRequest.body!) as Map<String, dynamic>;

  @override
  Future<ApiResponse> send(ApiRequest request) {
    requests.add(request);
    return _handler(request);
  }

  @override
  void close() => closed = true;
}

/// A `POST /init` answer with everything filled in.
Map<String, Object?> startBody({
  String? token = 'tok-1',
  bool anonymous = false,
  String action = 'none',
  String channel = 'store',
  Map<String, bool> features = const {},
}) => {
  'install': anonymous
      ? null
      : {
          'id': '3f2a1e40-9a1c-4f0e-8b1d-2c9e7a5b6d10',
          'first_run': true,
          'registered_at': '2026-08-22T10:00:00Z',
        },
  'account': anonymous
      ? null
      : {
          'id': 'abc123',
          'display_name': 'Guest abc123',
          'email': null,
          'is_guest': true,
          'is_admin': false,
        },
  'session': anonymous
      ? null
      : {'token': token, 'expires_at': '2027-08-22T10:00:00Z'},
  'update': {
    'action': action,
    'channel': channel,
    'current': '1.0.0',
    'latest': '1.2.0',
    'minimum': '1.0.0',
    'url': 'https://play.google.com/store/apps/details?id=com.supermovies.app',
  },
  'features': features,
  'server_time': '2026-08-22T10:00:00Z',
};

/// A `POST /auth/*` answer.
Map<String, Object?> identityBody({
  String token = 'tok-2',
  bool guest = false,
  String? email = 'vi@example.com',
}) => {
  'session': {'token': token, 'expires_at': '2027-08-22T10:00:00Z'},
  'account': {
    'id': 'abc123',
    'display_name': 'vi',
    'email': guest ? null : email,
    'is_guest': guest,
    'is_admin': false,
  },
};

SuperMoviesApi apiFor(
  FakeTransport transport, {
  String? token,
  void Function(String?)? onToken,
}) => SuperMoviesApi(
  baseUrl: Uri.parse('https://api.test/'),
  transport: transport,
  token: token,
  onToken: onToken,
);
