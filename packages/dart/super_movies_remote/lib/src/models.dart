import 'dart:math';

import 'package:super_movies_api/super_movies_api.dart';

/// A JSON object, which is what a command's params and a box's state both are.
typedef Payload = Map<String, Object?>;

final _dice = Random();

String _newId() {
  // Short and unique enough to tell one press from the next. Not a secret:
  // this only has to survive being echoed back in a log line.
  final bits = List.generate(4, (_) => _dice.nextInt(1 << 16));
  return bits.map((value) => value.toRadixString(36).padLeft(4, '0')).join();
}

/// One button press on its way to a box.
///
/// There is no reply channel: a command is handed to whoever is listening and
/// that is the end of it. [id] is what makes that workable — a box that wants
/// to answer puts the id back in its state, and a remote that resends knows
/// whether it is resending or repeating.
final class Command {
  Command({required this.method, Payload params = const {}, String? id})
    : id = id ?? _newId(),
      params = Map.unmodifiable(params);

  factory Command.fromJson(JsonMap json) {
    const owner = 'Command';
    return Command(
      id: json.requireString('id', owner: owner),
      method: json.requireString('method', owner: owner),
      params: switch (json['params']) {
        final Map<String, dynamic> params => params,
        _ => const {},
      },
    );
  }

  /// The remote's own. Comes back in the [Delivery].
  final String id;

  /// Lower-case, dotted: `play`, `player.seek`, `volume_up`. The API refuses
  /// anything else before it reaches a box.
  final String method;

  final Payload params;

  JsonMap toJson() => {'id': id, 'method': method, 'params': params};

  @override
  String toString() => 'Command($method, $id)';
}

/// What became of a command.
final class Delivery {
  const Delivery({required this.id, required this.listeners});

  factory Delivery.fromJson(JsonMap json) {
    const owner = 'Delivery';
    return Delivery(
      id: json.requireString('id', owner: owner),
      listeners: json.requireInt('listeners', owner: owner),
    );
  }

  final String id;

  /// How many streams were open on that box when this was sent.
  final int listeners;

  /// The honest version of "did that work". False means nobody was connected —
  /// which is a different thing from the box having refused.
  bool get heard => listeners > 0;

  @override
  String toString() => 'Delivery($id, $listeners listening)';
}

/// What a box says it is doing.
///
/// The payload is whatever the app puts in it — this package has no opinion,
/// and neither does the server. Read it with [value] and [flag] rather than by
/// indexing, so a field that is missing or the wrong type is a `null` here
/// instead of a cast error three frames away.
final class DeviceState {
  DeviceState({required this.at, Payload data = const {}})
    : data = Map.unmodifiable(data);

  factory DeviceState.fromJson(JsonMap json) => DeviceState(
    at: json.requireDateTime('at', owner: 'DeviceState'),
    data: switch (json['state']) {
      final Map<String, dynamic> state => state,
      _ => const {},
    },
  );

  /// The server's clock, not the box's — a television that has been unplugged
  /// for a month often believes it is 1970.
  final DateTime at;

  final Payload data;

  T? value<T>(String key) {
    final found = data[key];
    return found is T ? found : null;
  }

  bool flag(String key, {bool orElse = false}) => value<bool>(key) ?? orElse;

  @override
  String toString() => 'DeviceState(${data.keys.join(', ')})';
}

/// A box somebody may point a remote at.
final class Device {
  const Device({
    required this.id,
    required this.platform,
    required this.version,
    required this.lastSeenAt,
  });

  factory Device.fromJson(JsonMap json) {
    const owner = 'Device';
    return Device(
      id: json.requireString('id', owner: owner),
      platform: json.requireString('platform', owner: owner),
      version: json.requireString('version', owner: owner),
      lastSeenAt: json.requireDateTime('last_seen_at', owner: owner),
    );
  }

  /// The install's public id — what goes in the URL of every call about it.
  final String id;

  final String platform;
  final String version;
  final DateTime lastSeenAt;

  @override
  String toString() => 'Device($id, $platform $version)';
}
