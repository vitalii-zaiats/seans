import 'models.dart';

/// What a phone can do, stated as a capability rather than as a set of URLs.
///
/// The point of the split is what comes next. Today the only implementation
/// goes through the API, which is the only thing that works when the two
/// devices are on different networks. On the same wi-fi there is a shorter road
/// — find the box with mDNS, talk to it directly — and that is a second
/// implementation of these two interfaces, with [Remote] and [Receiver]
/// unchanged above them.
abstract interface class RemoteChannel {
  /// The boxes this account may drive.
  Future<List<Device>> devices();

  /// Hand a command to whoever is listening on [deviceId].
  Future<Delivery> send(String deviceId, Command command);

  /// What that box is doing, starting with what it is doing now.
  Stream<DeviceState> states(String deviceId);

  void close();
}

/// What a box can do. Deliberately not the same interface: a box has no
/// business being able to send itself commands.
abstract interface class ReceiverChannel {
  /// Buttons, as they are pressed.
  Stream<Command> commands();

  /// Say what is happening. This is the only way back — there is no reply to a
  /// command, so a box that wants to answer one answers in its state.
  Future<void> report(Payload state);

  void close();
}
