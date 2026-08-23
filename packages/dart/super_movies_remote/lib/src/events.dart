import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:super_movies_api/super_movies_api.dart';

import 'sse.dart';

/// Where a stream of server-sent events comes from.
///
/// A seam of its own because `Transport` cannot serve one: it hands back a
/// finished `ApiResponse`, and this connection never finishes.
///
/// **On the web**, do not reach for the browser's `EventSource`: it cannot send
/// an `Authorization` header, and this API takes a bearer token. Supply an
/// implementation over `fetch` with a `ReadableStream` instead — that carries
/// headers and streams properly. Putting the token in the query string would
/// also work, and would write it into every access log between here and there.
abstract interface class EventStream {
  /// Opens one connection. The stream ends, or throws, when it drops — see
  /// [reconnecting] for the part that puts it back.
  Stream<ServerSentEvent> connect(Uri url, {Map<String, String> headers});

  void close();
}

/// An [EventStream] over `package:http`.
final class HttpEventStream implements EventStream {
  HttpEventStream({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Stream<ServerSentEvent> connect(
    Uri url, {
    Map<String, String> headers = const {},
  }) async* {
    final request = http.Request('GET', url)
      ..headers.addAll({...headers, 'Accept': 'text/event-stream'});

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiNetworkException(url, error);
    }

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw ApiHttpException(
        statusCode: response.statusCode,
        uri: url,
        detail: detailOf(body, response.statusCode),
        body: body,
      );
    }

    yield* parseEvents(response.stream);
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Whether an error is worth trying again.
///
/// The default says no to the three that never get better on their own: a stale
/// token, a device that is not yours, and one that does not exist. A television
/// reconnecting to a 401 every second until somebody notices is the failure
/// this exists to prevent.
bool transient(Object error) => switch (error) {
  ApiHttpException(
    :final isUnauthorized,
    :final isForbidden,
    :final isNotFound,
  ) =>
    !(isUnauthorized || isForbidden || isNotFound),
  _ => true,
};

/// Keeps [open] open.
///
/// Yields whatever the stream yields; when it ends or fails, waits and opens a
/// new one. The wait doubles up to [ceiling] and carries jitter, so a server
/// coming back up does not meet every television it serves in the same second.
///
/// Built on a controller rather than as an `async*` generator, and that is not
/// a style choice. A generator only notices that its listener has gone when it
/// next reaches a `yield` — so one asleep in its backoff would ignore
/// `cancel()` for as long as the wait had grown to, and then open a fresh
/// connection on the way out. Here the timer and the subscription are held, so
/// cancelling stops both at once.
Stream<T> reconnecting<T>(
  Stream<T> Function() open, {
  Duration first = const Duration(seconds: 1),
  Duration ceiling = const Duration(seconds: 30),
  bool Function(Object error) retryWhen = transient,
  void Function(Object? error, Duration wait)? onRetry,
  Random? random,
}) {
  final dice = random ?? Random();
  late final StreamController<T> out;
  StreamSubscription<T>? current;
  Timer? waiting;
  var attempt = 0;
  var stopped = false;

  void connect() {
    if (stopped) return;

    void retryAfter(Object? error) {
      current = null;
      if (stopped) return;
      final wait = backoff(
        attempt++,
        first: first,
        ceiling: ceiling,
        random: dice,
      );
      onRetry?.call(error, wait);
      waiting = Timer(wait, connect);
    }

    final Stream<T> source;
    try {
      source = open();
    } catch (error) {
      if (!retryWhen(error)) {
        out.addError(error);
        unawaited(out.close());
        return;
      }
      retryAfter(error);
      return;
    }

    current = source.listen(
      (item) {
        // Anything at all means the connection works, so the next drop starts
        // from a short wait rather than from wherever the last one got to.
        attempt = 0;
        out.add(item);
      },
      onError: (Object error, StackTrace stack) {
        if (!retryWhen(error)) {
          out.addError(error, stack);
          unawaited(out.close());
          stopped = true;
          return;
        }
        retryAfter(error);
      },
      onDone: () => retryAfter(null),
      cancelOnError: true,
    );
  }

  out = StreamController<T>(
    onListen: connect,
    onPause: () => current?.pause(),
    onResume: () => current?.resume(),
    onCancel: () async {
      stopped = true;
      waiting?.cancel();
      await current?.cancel();
    },
  );

  return out.stream;
}

/// Exponential, capped, and jittered to 70–130%. Visible for tests.
Duration backoff(
  int attempt, {
  Duration first = const Duration(seconds: 1),
  Duration ceiling = const Duration(seconds: 30),
  Random? random,
}) {
  final grown = first.inMilliseconds * (1 << attempt.clamp(0, 16));
  final capped = grown.clamp(first.inMilliseconds, ceiling.inMilliseconds);
  final spread = 0.7 + (random ?? Random()).nextDouble() * 0.6;
  return Duration(milliseconds: (capped * spread).round());
}
