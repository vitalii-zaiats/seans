import 'dart:async';
import 'dart:convert';

/// One dispatched server-sent event.
final class ServerSentEvent {
  const ServerSentEvent({
    required this.event,
    required this.data,
    this.id,
    this.retry,
  });

  /// The `event:` field, or `message` when the server named none.
  final String event;

  /// The `data:` payload. Several `data:` lines arrive joined by newlines.
  final String data;

  /// The last `id:` the connection saw. Persistent by spec — it is not reset
  /// between events — and `null` for a server that sends none, which ours does
  /// deliberately: resuming would mean replaying, and a replayed command is an
  /// instruction acted on at the wrong moment.
  final String? id;

  /// How long the server asked us to wait before reconnecting.
  final Duration? retry;

  @override
  String toString() => 'ServerSentEvent($event, ${data.length} chars)';
}

/// Parses the `text/event-stream` wire format.
///
/// Written out rather than pulled in: the format is a dozen rules, and the two
/// that matter here are easy to get wrong. A line starting with `:` is a
/// comment, which is what every keepalive on this connection is; and a blank
/// line with no `data:` before it dispatches nothing at all rather than an
/// empty event.
Stream<ServerSentEvent> parseEvents(Stream<List<int>> bytes) => bytes
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .transform(_dispatcher);

final _dispatcher = StreamTransformer<String, ServerSentEvent>.fromBind((
  lines,
) async* {
  var event = '';
  final data = StringBuffer();
  var hasData = false;
  String? id;
  Duration? retry;

  await for (final line in lines) {
    if (line.isEmpty) {
      if (!hasData) {
        // A blank line after nothing but comments. Per spec the event type
        // resets and nothing is dispatched — which is exactly what makes a
        // keepalive invisible to whoever is listening.
        event = '';
        continue;
      }
      yield ServerSentEvent(
        event: event.isEmpty ? 'message' : event,
        data: data.toString(),
        id: id,
        retry: retry,
      );
      event = '';
      data.clear();
      hasData = false;
      continue;
    }

    if (line.startsWith(':')) continue;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    // Exactly one leading space belongs to the framing, not to the value.
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (hasData) data.write('\n');
        data.write(value);
        hasData = true;
      case 'id':
        id = value;
      case 'retry':
        final milliseconds = int.tryParse(value);
        if (milliseconds != null) retry = Duration(milliseconds: milliseconds);
    }
  }
});
