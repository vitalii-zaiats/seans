import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:super_movies_api/super_movies_api.dart';
import 'package:super_movies_remote/super_movies_remote.dart';

/// A [Transport] that answers from memory and records what it was asked for.
final class FakeTransport implements Transport {
  FakeTransport(this._handler);

  factory FakeTransport.json(Object body, {int statusCode = 200}) =>
      FakeTransport(
        (_) async => ApiResponse.bytes(
          statusCode: statusCode,
          bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
        ),
      );

  final Future<ApiResponse> Function(ApiRequest request) _handler;

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

/// An [EventStream] the test drives by hand.
final class FakeEventStream implements EventStream {
  FakeEventStream([this._script]);

  /// One connection's worth of events, replayed each time it is opened.
  final List<ServerSentEvent>? _script;

  final List<Uri> opened = [];
  final List<Map<String, String>> headers = [];
  final _live = StreamController<ServerSentEvent>.broadcast();

  bool closed = false;

  /// Whether anybody is actually attached yet. `opened` is recorded before the
  /// generator reaches `yield*`, so a test that emits on the strength of it
  /// emits into a broadcast stream nobody is listening to.
  bool get listening => _live.hasListener;

  /// Push an event into every open connection.
  void emit(String event, Object data) =>
      _live.add(ServerSentEvent(event: event, data: jsonEncode(data)));

  /// Push something that will not parse.
  void emitRaw(String event, String data) =>
      _live.add(ServerSentEvent(event: event, data: data));

  @override
  Stream<ServerSentEvent> connect(
    Uri url, {
    Map<String, String> headers = const {},
  }) async* {
    opened.add(url);
    this.headers.add(headers);
    for (final event in _script ?? const <ServerSentEvent>[]) {
      yield event;
    }
    yield* _live.stream;
  }

  @override
  void close() {
    closed = true;
    _live.close();
  }
}
