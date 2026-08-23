import 'dart:async';

import 'channel.dart';
import 'models.dart';

/// What a box does when a button is pressed.
typedef Handler = FutureOr<void> Function(Command command);

/// The box.
///
/// ```dart
/// final receiver = Receiver(
///   channel: ApiReceiverChannel(baseUrl: base, token: () => api.token),
/// );
///
/// receiver.serve({
///   'play': (command) => player.play(command.params['id']! as String),
///   'pause': (_) => player.pause(),
/// });
///
/// await receiver.report({'playing': true, 'title': film.name});
/// ```
///
/// A command is an instruction about *now*. Nothing is queued and nothing is
/// replayed, so a box that was asleep wakes up with nothing to catch up on —
/// which is the behaviour a remote control should have. What was pressed while
/// the television was off did not happen.
final class Receiver {
  const Receiver({required this.channel});

  final ReceiverChannel channel;

  /// Buttons, as they are pressed. Reconnects by itself.
  Stream<Command> commands() => channel.commands();

  /// Say what is happening.
  ///
  /// The only way back: there is no reply to a command, so a box that wants to
  /// answer one answers here. Putting the command's [Command.id] in the payload
  /// is the convention that makes that legible to whoever sent it.
  Future<void> report(Payload state) => channel.report(state);

  /// Run [handlers] until the subscription is cancelled.
  ///
  /// A handler that throws is reported to [onError] and otherwise ignored: one
  /// command the app could not carry out must not take the connection down with
  /// it, because the next one is somebody pressing the button again.
  StreamSubscription<Command> serve(
    Map<String, Handler> handlers, {
    Handler? onUnknown,
    void Function(Command command, Object error, StackTrace stack)? onError,
  }) => commands().listen((command) async {
    final handler = handlers[command.method] ?? onUnknown;
    if (handler == null) return;
    try {
      await handler(command);
    } catch (error, stack) {
      onError?.call(command, error, stack);
    }
  });

  void close() => channel.close();
}
