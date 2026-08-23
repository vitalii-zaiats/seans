/// Driving a box from a phone, and being the box.
///
/// Two roles, one package, because both ends of this are Dart and they have to
/// agree about the wire. [Remote] sends commands and watches state; [Receiver]
/// receives commands and reports state. Neither knows how — that is a
/// [RemoteChannel] or a [ReceiverChannel], and the ones here go through the
/// API.
///
/// There is no pairing code and no shared secret: **you may drive a box you are
/// signed in on.** Getting signed in is a different story, and
/// `super_movies_api` tells it — a television shows a code, a phone approves,
/// and after that the two are one account.
library;

export 'src/api_channel.dart'
    show ApiReceiverChannel, ApiRemoteChannel, OnMalformed;
export 'src/channel.dart' show ReceiverChannel, RemoteChannel;
export 'src/events.dart'
    show EventStream, HttpEventStream, backoff, reconnecting, transient;
export 'src/models.dart' show Command, Delivery, Device, DeviceState, Payload;
export 'src/receiver.dart' show Handler, Receiver;
export 'src/remote.dart' show Remote;
export 'src/sse.dart' show ServerSentEvent, parseEvents;
