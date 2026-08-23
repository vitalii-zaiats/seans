import 'dart:convert';

import 'package:super_movies_remote/super_movies_remote.dart';
import 'package:test/test.dart';

/// The wire, cut into [chunk]-byte pieces — because a real one is cut wherever
/// the network felt like it, and a parser that only works on whole lines is a
/// parser that works until it does not.
Stream<List<int>> wire(String text, {int chunk = 4096}) async* {
  final bytes = utf8.encode(text);
  for (var at = 0; at < bytes.length; at += chunk) {
    yield bytes.sublist(at, (at + chunk).clamp(0, bytes.length));
  }
}

Future<List<ServerSentEvent>> parse(String text, {int chunk = 4096}) =>
    parseEvents(wire(text, chunk: chunk)).toList();

void main() {
  test('a named event with a payload', () async {
    final events = await parse('event: command\ndata: {"id":"1"}\n\n');

    expect(events, hasLength(1));
    expect(events.single.event, 'command');
    expect(events.single.data, '{"id":"1"}');
  });

  test('an unnamed event is a message, as the spec says', () async {
    final events = await parse('data: hello\n\n');

    expect(events.single.event, 'message');
  });

  test('exactly one leading space is framing, the rest is the value', () async {
    final events = await parse('data:  two spaces\n\n');

    expect(events.single.data, ' two spaces');
  });

  test('several data lines join with newlines', () async {
    final events = await parse('data: one\ndata: two\ndata: three\n\n');

    expect(events.single.data, 'one\ntwo\nthree');
  });

  test('an empty data line is a newline, not nothing', () async {
    final events = await parse('data: one\ndata:\ndata: three\n\n');

    expect(events.single.data, 'one\n\nthree');
  });

  test('a keepalive is invisible', () async {
    // This is what a quiet stream looks like for hours at a time.
    final events = await parse(
      ': open\n\n: ping\n\n: ping\n\nevent: state\ndata: {}\n\n',
    );

    expect(events, hasLength(1));
    expect(events.single.event, 'state');
  });

  test('a blank line with nothing before it dispatches nothing', () async {
    expect(await parse('\n\n\n'), isEmpty);
  });

  test('a comment does not reset the event that is being built', () async {
    final events = await parse('event: state\n: still here\ndata: {}\n\n');

    expect(events.single.event, 'state');
  });

  test('the event type resets between events', () async {
    final events = await parse('event: command\ndata: a\n\ndata: b\n\n');

    expect(events.map((event) => event.event), ['command', 'message']);
  });

  test('id and retry are read', () async {
    final events = await parse('id: 7\nretry: 4500\ndata: x\n\n');

    expect(events.single.id, '7');
    expect(events.single.retry, const Duration(milliseconds: 4500));
  });

  test('an id persists across events, as the spec requires', () async {
    final events = await parse('id: 7\ndata: a\n\ndata: b\n\n');

    expect(events.map((event) => event.id), ['7', '7']);
  });

  test('a field nobody knows is ignored rather than fatal', () async {
    final events = await parse('wat: 1\ndata: x\n\n');

    expect(events.single.data, 'x');
  });

  test('a field with no colon at all is ignored', () async {
    final events = await parse('nonsense\ndata: x\n\n');

    expect(events.single.data, 'x');
  });

  test('carriage returns are line endings too', () async {
    final events = await parse('event: state\r\ndata: {}\r\n\r\n');

    expect(events.single.event, 'state');
    expect(events.single.data, '{}');
  });

  test('a frame split across chunks still parses', () async {
    final events = await parse(
      'event: command\ndata: {"id":"1","method":"play"}\n\n',
      chunk: 3,
    );

    expect(events.single.event, 'command');
    expect(events.single.data, '{"id":"1","method":"play"}');
  });

  test('a multi-byte character split across chunks survives', () async {
    // One byte at a time, so every Cyrillic character straddles a boundary.
    final events = await parse('data: Хрещений батько\n\n', chunk: 1);

    expect(events.single.data, 'Хрещений батько');
  });

  test('a frame nobody closed is not dispatched', () async {
    // The connection dropped mid-event. Half an instruction is not one.
    expect(await parse('event: command\ndata: {"id":'), isEmpty);
  });
}
