import 'channel.dart';
import 'models.dart';

/// The phone.
///
/// ```dart
/// final remote = Remote(
///   channel: ApiRemoteChannel(baseUrl: base, token: () => api.token),
/// );
///
/// final boxes = await remote.devices();
/// await remote.send(boxes.first.id, 'play', params: {'id': 'tt0111161'});
///
/// await for (final state in remote.watch(boxes.first.id)) {
///   setState(() => playing = state.flag('playing'));
/// }
/// ```
///
/// You may drive a box you are signed in on, and nothing else. A box you have
/// never signed into answers as if it did not exist — telling a stranger that a
/// device exists is telling them something.
final class Remote {
  const Remote({required this.channel});

  final RemoteChannel channel;

  /// Every box this account is signed in on.
  ///
  /// There is no separate list of "my devices" to fall out of step with
  /// reality: signing a box in claims it, signing it out gives it up.
  Future<List<Device>> devices() => channel.devices();

  /// Press a button.
  ///
  /// The answer says how many streams were open on that box, not what it did —
  /// there is no reply to a command. [Delivery.heard] is the honest form of
  /// "did that work": false means nobody was listening, which is a different
  /// thing from the box refusing.
  Future<Delivery> send(
    String deviceId,
    String method, {
    Payload params = const {},
    String? id,
  }) => channel.send(deviceId, Command(method: method, params: params, id: id));

  /// What a box is doing, starting with what it is doing right now.
  ///
  /// The first thing to arrive is the current state rather than the next
  /// change, so a phone that has just been unlocked has something to draw. The
  /// stream reconnects by itself and ends only on a refusal that will not get
  /// better — a stale token, or a box that is not yours.
  Stream<DeviceState> watch(String deviceId) => channel.states(deviceId);

  void close() => channel.close();
}
