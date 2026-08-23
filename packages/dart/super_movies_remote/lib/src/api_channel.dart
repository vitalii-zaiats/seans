import 'dart:async';
import 'dart:convert';

import 'package:super_movies_api/super_movies_api.dart';

import 'channel.dart';
import 'events.dart';
import 'models.dart';
import 'sse.dart';

/// What a malformed frame is handed to, if anybody is listening.
typedef OnMalformed = void Function(ServerSentEvent event, Object error);

/// The shared half of both channels: where to call, and with whose token.
///
/// The token arrives as a callback rather than a string because it changes
/// underneath us — a television that was a guest becomes an account the moment
/// somebody signs it in with a phone, and a channel holding the old string
/// would keep reconnecting as nobody.
final class _Calls {
  _Calls({
    required Uri baseUrl,
    required this.token,
    required this.transport,
    required this.timeout,
  }) : baseUrl = Uri.parse(baseUrl.toString().replaceAll(RegExp(r'/+$'), ''));

  final Uri baseUrl;
  final String? Function() token;
  final Transport transport;
  final Duration timeout;

  Uri uriFor(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> headers({bool json = false}) {
    final held = token();
    return {
      'Accept': 'application/json',
      if (held != null) 'Authorization': 'Bearer $held',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<JsonMap> get(String path) => _send('GET', path);

  Future<JsonMap> post(String path, JsonMap body) =>
      _send('POST', path, body: body);

  Future<JsonMap> _send(String method, String path, {JsonMap? body}) async {
    final uri = uriFor(path);
    final ApiResponse response;
    try {
      response = await transport
          .send(
            ApiRequest(
              method: method,
              url: uri,
              headers: headers(json: body != null),
              body: body == null ? null : jsonEncode(body),
            ),
          )
          .timeout(timeout);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiNetworkException(uri, error);
    }
    return decodeObject(response, uri);
  }
}

/// Everything a phone does, over the API.
///
/// Commands are ordinary POSTs; state arrives on a server-sent event stream
/// that puts itself back together when it drops.
final class ApiRemoteChannel implements RemoteChannel {
  ApiRemoteChannel({
    required Uri baseUrl,
    required String? Function() token,
    Transport? transport,
    EventStream? events,
    Duration timeout = const Duration(seconds: 20),
    this.onMalformed,
  }) : _calls = _Calls(
         baseUrl: baseUrl,
         token: token,
         transport: transport ?? HttpTransport(),
         timeout: timeout,
       ),
       _events = events ?? HttpEventStream();

  final _Calls _calls;
  final EventStream _events;

  /// Where a frame that will not parse goes. Left unset, one is skipped — a
  /// single bad message is not a reason to drop a connection a television has
  /// been holding for a month.
  final OnMalformed? onMalformed;

  @override
  Future<List<Device>> devices() async {
    final answer = await _calls.get('/devices');
    return switch (answer['items']) {
      final List<dynamic> items => [
        for (final item in items)
          if (item is Map<String, dynamic>) Device.fromJson(item),
      ],
      _ => const [],
    };
  }

  @override
  Future<Delivery> send(String deviceId, Command command) async =>
      Delivery.fromJson(
        await _calls.post(
          '/device/${Uri.encodeComponent(deviceId)}/rpc',
          command.toJson(),
        ),
      );

  @override
  Stream<DeviceState> states(String deviceId) => _frames(
    _events,
    _calls,
    '/device/${Uri.encodeComponent(deviceId)}/events',
    want: 'state',
    parse: DeviceState.fromJson,
    onMalformed: onMalformed,
  );

  @override
  void close() {
    _calls.transport.close();
    _events.close();
  }
}

/// Everything a box does, over the API.
///
/// It never names itself: the session it is holding already says which install
/// it is, and a device that could name itself could name somebody else's.
final class ApiReceiverChannel implements ReceiverChannel {
  ApiReceiverChannel({
    required Uri baseUrl,
    required String? Function() token,
    Transport? transport,
    EventStream? events,
    Duration timeout = const Duration(seconds: 20),
    this.onMalformed,
  }) : _calls = _Calls(
         baseUrl: baseUrl,
         token: token,
         transport: transport ?? HttpTransport(),
         timeout: timeout,
       ),
       _events = events ?? HttpEventStream();

  final _Calls _calls;
  final EventStream _events;

  /// See [ApiRemoteChannel.onMalformed].
  final OnMalformed? onMalformed;

  @override
  Stream<Command> commands() => _frames(
    _events,
    _calls,
    '/device/events',
    want: 'command',
    parse: Command.fromJson,
    onMalformed: onMalformed,
  );

  @override
  Future<void> report(Payload state) async {
    await _calls.post('/device/state', {'state': state});
  }

  @override
  void close() {
    _calls.transport.close();
    _events.close();
  }
}

/// One reconnecting stream of a single named event, already parsed.
///
/// A transformer rather than an `async*` loop, for the same reason
/// [reconnecting] is a controller: a generator suspended in `await for` does
/// not notice that its listener has gone until something arrives to wake it,
/// and on a quiet television that is never. A transformer passes the
/// cancellation straight through.
Stream<T> _frames<T>(
  EventStream events,
  _Calls calls,
  String path, {
  required String want,
  required T Function(JsonMap json) parse,
  OnMalformed? onMalformed,
}) =>
    reconnecting(
      () => events.connect(calls.uriFor(path), headers: calls.headers()),
    ).transform(
      StreamTransformer<ServerSentEvent, T>.fromHandlers(
        handleData: (event, sink) {
          if (event.event != want) return;
          try {
            sink.add(parse(jsonDecode(event.data) as JsonMap));
          } catch (error) {
            onMalformed?.call(event, error);
          }
        },
      ),
    );
