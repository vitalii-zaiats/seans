import 'dart:async';

import 'package:super_movies_api/super_movies_api.dart';
import 'package:super_movies_remote/super_movies_remote.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

final base = Uri.parse('https://api.test/');

Map<String, Object?> stateFrame(Map<String, Object?> data) => {
  'at': '2026-08-23T10:00:00Z',
  'state': data,
};

void main() {
  group('the phone', () {
    test('lists the boxes it may drive', () async {
      final transport = FakeTransport.json({
        'items': [
          {
            'id': '2c16a0de-0000-4000-8000-000000000000',
            'platform': 'android',
            'version': '1.0.0',
            'last_seen_at': '2026-08-23T09:00:00Z',
          },
        ],
      });
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: transport,
          events: FakeEventStream(),
        ),
      );

      final devices = await remote.devices();

      expect(transport.lastRequest.url.path, '/devices');
      expect(transport.lastRequest.headers['Authorization'], 'Bearer phone');
      expect(devices.single.platform, 'android');
      expect(devices.single.version, '1.0.0');
    });

    test('an empty listing is a listing, not a failure', () async {
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: FakeEventStream(),
        ),
      );

      expect(await remote.devices(), isEmpty);
    });

    test('sends a command and reports who heard it', () async {
      final transport = FakeTransport.json({'id': 'cmd-1', 'listeners': 1});
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: transport,
          events: FakeEventStream(),
        ),
      );

      final delivery = await remote.send(
        'dev-1',
        'play',
        params: {'id': 'tt0111161'},
        id: 'cmd-1',
      );

      expect(transport.lastRequest.method, 'POST');
      expect(transport.lastRequest.url.path, '/device/dev-1/rpc');
      expect(transport.lastBody, {
        'id': 'cmd-1',
        'method': 'play',
        'params': {'id': 'tt0111161'},
      });
      expect(delivery.heard, isTrue);
    });

    test('nobody listening is an answer, not an error', () async {
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: FakeTransport.json({'id': 'cmd-1', 'listeners': 0}),
          events: FakeEventStream(),
        ),
      );

      expect((await remote.send('dev-1', 'pause')).heard, isFalse);
    });

    test('a box that is not yours is a refusal from the API', () async {
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: FakeTransport.json({'detail': 'no such device'}, statusCode: 404),
          events: FakeEventStream(),
        ),
      );

      await expectLater(
        remote.send('somebody-elses', 'play'),
        throwsA(
          isA<ApiHttpException>()
              .having((error) => error.isNotFound, 'isNotFound', isTrue)
              .having((error) => error.message, 'message', 'no such device'),
        ),
      );
    });

    test('watching a box yields its state', () async {
      final events = FakeEventStream();
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final seen = remote.watch('dev-1').take(2).toList();
      await pumpUntil(() => events.listening);

      events.emit('state', stateFrame({'playing': true, 'title': 'Дюна'}));
      events.emit('state', stateFrame({'playing': false}));

      final states = await seen;
      expect(events.opened.first.path, '/device/dev-1/events');
      expect(events.headers.first['Authorization'], 'Bearer phone');
      expect(states.first.flag('playing'), isTrue);
      expect(states.first.value<String>('title'), 'Дюна');
      expect(states.last.flag('playing'), isFalse);
      expect(states.first.at.isUtc, isTrue);
    });

    test('a command on the wire never reaches a state watcher', () async {
      final events = FakeEventStream();
      final remote = Remote(
        channel: ApiRemoteChannel(
          baseUrl: base,
          token: () => 'phone',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final seen = remote.watch('dev-1').take(1).toList();
      await pumpUntil(() => events.listening);

      events.emit('command', {'id': '1', 'method': 'play'});
      events.emit('state', stateFrame({'playing': true}));

      expect((await seen).single.flag('playing'), isTrue);
    });
  });

  group('the box', () {
    test('receives commands', () async {
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final seen = receiver.commands().take(1).toList();
      await pumpUntil(() => events.listening);

      events.emit('command', {
        'id': 'cmd-1',
        'method': 'play',
        'params': {'id': 'tt0111161'},
      });

      final command = (await seen).single;
      // The box never names itself: its session says which install it is.
      expect(events.opened.first.path, '/device/events');
      expect(command.method, 'play');
      expect(command.params['id'], 'tt0111161');
    });

    test('reports its state', () async {
      final transport = FakeTransport.json(const <String, Object?>{}, statusCode: 204);
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: transport,
          events: FakeEventStream(),
        ),
      );

      await receiver.report({'playing': true});

      expect(transport.lastRequest.url.path, '/device/state');
      expect(transport.lastBody, {
        'state': {'playing': true},
      });
    });

    test('serve dispatches by method name', () async {
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final played = <String>[];
      final unknown = <String>[];
      final subscription = receiver.serve(
        {'play': (command) => played.add(command.params['id']! as String)},
        onUnknown: (command) => unknown.add(command.method),
      );
      await pumpUntil(() => events.listening);

      events.emit('command', {
        'id': '1',
        'method': 'play',
        'params': {'id': 'tt0111161'},
      });
      events.emit('command', {'id': '2', 'method': 'levitate'});
      await pumpUntil(() => played.isNotEmpty && unknown.isNotEmpty);
      await subscription.cancel();

      expect(played, ['tt0111161']);
      expect(unknown, ['levitate']);
    });

    test('a handler that throws does not take the connection down', () async {
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final failures = <String>[];
      final after = <String>[];
      final subscription = receiver.serve(
        {
          'play': (_) => throw StateError('no player'),
          'pause': (command) => after.add(command.method),
        },
        onError: (command, error, _) => failures.add(command.method),
      );
      await pumpUntil(() => events.listening);

      events.emit('command', {'id': '1', 'method': 'play'});
      events.emit('command', {'id': '2', 'method': 'pause'});
      await pumpUntil(() => after.isNotEmpty);
      await subscription.cancel();

      expect(failures, ['play']);
      // The next press still arrives, which is the whole point.
      expect(after, ['pause']);
    });

    test('a frame that will not parse is skipped, not fatal', () async {
      final events = FakeEventStream();
      final malformed = <Object>[];
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
          onMalformed: (_, error) => malformed.add(error),
        ),
      );

      final seen = receiver.commands().take(1).toList();
      await pumpUntil(() => events.listening);

      events.emitRaw('command', 'not json at all');
      events.emit('command', {'id': '1', 'method': 'pause'});

      expect((await seen).single.method, 'pause');
      expect(malformed, hasLength(1));
    });

    test('the token is read per connection, not captured once', () async {
      // A television that was a guest becomes an account the moment somebody
      // signs it in with a phone. A channel holding the old string would keep
      // reconnecting as nobody.
      var token = 'guest';
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => token,
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final first = receiver.commands().take(1).toList();
      await pumpUntil(() => events.listening);
      events.emit('command', {'id': '1', 'method': 'pause'});
      await first;

      token = 'linked';
      final second = receiver.commands().take(1).toList();
      await pumpUntil(() => events.opened.length > 1 && events.listening);
      events.emit('command', {'id': '2', 'method': 'pause'});
      await second;

      expect(events.headers.first['Authorization'], 'Bearer guest');
      expect(events.headers.last['Authorization'], 'Bearer linked');
    });
  });

  group('letting go', () {
    test('cancelling a stream returns at once, not after the backoff', () async {
      // The first version of this waited for whatever the retry delay had grown
      // to, and then opened one more connection on the way out. An app closing
      // a screen would hang for up to thirty seconds.
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final subscription = receiver.commands().listen(null);
      await pumpUntil(() => events.listening);

      final stopwatch = Stopwatch()..start();
      await subscription.cancel();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
      expect(events.listening, isFalse);
    });

    test('a served box lets go just as quickly', () async {
      final events = FakeEventStream();
      final receiver = Receiver(
        channel: ApiReceiverChannel(
          baseUrl: base,
          token: () => 'tv',
          transport: FakeTransport.json(const <String, Object?>{}),
          events: events,
        ),
      );

      final subscription = receiver.serve({'play': (_) {}});
      await pumpUntil(() => events.listening);

      final stopwatch = Stopwatch()..start();
      await subscription.cancel();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
    });
  });

  group('commands', () {
    test('an id is generated when nobody supplies one', () {
      final one = Command(method: 'play');
      final two = Command(method: 'play');

      expect(one.id, isNotEmpty);
      expect(one.id, isNot(two.id));
    });

    test('params are frozen once the command exists', () {
      final params = {'id': 'tt0111161'};
      final command = Command(method: 'play', params: params);
      params['id'] = 'something else';

      expect(command.params['id'], 'tt0111161');
      expect(() => command.params['x'] = 1, throwsUnsupportedError);
    });

    test('a state field of the wrong type reads as absent', () {
      final state = DeviceState(at: DateTime.utc(2026), data: {'playing': 'yes'});

      expect(state.value<bool>('playing'), isNull);
      expect(state.flag('playing'), isFalse);
      expect(state.flag('playing', orElse: true), isTrue);
      expect(state.value<String>('playing'), 'yes');
    });
  });
}

/// Waits for [ready], a little at a time. Cheaper and less flaky than guessing
/// at a delay long enough for whatever the event loop is doing.
Future<void> pumpUntil(bool Function() ready, {int tries = 200}) async {
  for (var attempt = 0; attempt < tries; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('condition never became true');
}
