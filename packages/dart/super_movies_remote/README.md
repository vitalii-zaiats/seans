# super_movies_remote

Driving a box from a phone, and being the box. Two roles, one package, because
both ends are Dart and they have to agree about the wire.

There is no pairing code here and no shared secret: **you may drive a box you are
signed in on.** Getting signed in is a different story, and
[`super_movies_api`](../super_movies_api) tells it — a television shows a code, a
phone approves, and after that the two are one account.

## The phone

```dart
final remote = Remote(
  channel: ApiRemoteChannel(baseUrl: base, token: () => api.token),
);

for (final box in await remote.devices()) {
  print('${box.platform} ${box.version}');
}

final delivery = await remote.send(box.id, 'play', params: {'id': 'tt0111161'});
if (!delivery.heard) showSnack('That box is not connected');

await for (final state in remote.watch(box.id)) {
  setState(() => playing = state.flag('playing'));
}
```

`watch` opens with what the box is doing *now* rather than with the next change,
so a phone that has just been unlocked has something to draw.

## The box

```dart
final receiver = Receiver(
  channel: ApiReceiverChannel(baseUrl: base, token: () => api.token),
);

receiver.serve({
  'play': (command) => player.play(command.params['id']! as String),
  'pause': (_) => player.pause(),
}, onUnknown: (command) => log('nobody handles ${command.method}'));

await receiver.report({'playing': true, 'title': film.name});
```

The box never names itself: the session it holds already says which install it
is, and a device that could name itself could name somebody else's.

## Three things about commands

**Nothing is queued and nothing is replayed.** A command is an instruction about
*now*. A box that was asleep wakes up with nothing to catch up on, which is what
a remote control should do — what was pressed while the television was off did
not happen.

**There is no reply.** `Delivery.heard` says how many streams were open, not what
the box did. A box that wants to answer answers in its state; putting the
command's `id` in that payload is the convention that makes it legible.

**The token is read per connection, not captured once.** Pass a callback. A
television that was a guest becomes an account the moment somebody signs it in
with a phone, and a channel holding the old string would reconnect as nobody.

## Reconnection

The event streams put themselves back together: exponential backoff to thirty
seconds, jittered so a server coming back does not meet every television in the
same second, and reset the moment anything arrives.

They give up on the three refusals that never get better on their own — a stale
token, a box that is not yours, one that does not exist. A television
reconnecting to a `401` every second until somebody notices is the failure that
rule exists to prevent; everything else is worth another go.

Cancelling a stream returns immediately, including mid-backoff. That is why
`reconnecting` is a controller and `_frames` is a transformer rather than either
being an `async*` loop: a generator only notices its listener has gone when it
next reaches a `yield`, and on a quiet connection that is never.

## Transports

`Remote` and `Receiver` know nothing about HTTP — they hold a `RemoteChannel` or
a `ReceiverChannel`. Today the only implementations go through the API, which is
the only thing that works when the two devices are on different networks. On the
same wi-fi there is a shorter road — find the box with mDNS, talk to it directly
— and that is a second pair of implementations with everything above unchanged.

**On the web**, do not use the browser's `EventSource`: it cannot send an
`Authorization` header, and this API takes a bearer token. Supply an
`EventStream` over `fetch` with a `ReadableStream` instead. Putting the token in
the query string would also work, and would write it into every access log
between here and there.
