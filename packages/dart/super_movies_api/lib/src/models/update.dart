import '../json.dart';

/// What the app should do about the version it is running.
enum UpdateAction {
  /// Nothing. This is the newest build we ship for this platform.
  none('none'),

  /// Newer exists. Worth offering, not worth blocking on.
  optional('optional'),

  /// Older than the floor. The app should not carry on as if it were current.
  required('required');

  const UpdateAction(this.wire);

  final String wire;

  static UpdateAction fromWire(String? wire) {
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    // An action we do not know is not an excuse to block somebody: an unknown
    // instruction means "carry on".
    return UpdateAction.none;
  }
}

/// Where a new version would come from.
///
/// This is not a preference, it is a consequence of who installed the app. A
/// build from the Play Store must be sent back to the Play Store — one that
/// sideloads its own APK gets pulled from the shop.
enum UpdateChannel {
  /// Open [UpdatePlan.url] — the shop's listing.
  store('store'),

  /// Download [UpdatePlan.url] and install it. Never a Play Store build.
  self('self'),

  /// Nothing to do. A reload *is* the new version.
  auto('auto');

  const UpdateChannel(this.wire);

  final String wire;

  static UpdateChannel fromWire(String? wire) {
    for (final channel in values) {
      if (channel.wire == wire) return channel;
    }
    return UpdateChannel.auto;
  }
}

/// The server's verdict on the version the app reported.
final class UpdatePlan {
  const UpdatePlan({
    required this.action,
    required this.channel,
    required this.current,
    required this.latest,
    required this.minimum,
    this.url,
  });

  factory UpdatePlan.fromJson(JsonMap json) {
    const owner = 'UpdatePlan';
    return UpdatePlan(
      action: UpdateAction.fromWire(json.stringOrNull('action')),
      channel: UpdateChannel.fromWire(json.stringOrNull('channel')),
      current: json.requireString('current', owner: owner),
      latest: json.requireString('latest', owner: owner),
      minimum: json.requireString('minimum', owner: owner),
      url: json.stringOrNull('url'),
    );
  }

  final UpdateAction action;
  final UpdateChannel channel;

  /// Echoed back, so a log line reads on its own.
  final String current;
  final String latest;
  final String minimum;

  /// Where to go. `null` when there is nowhere to go — an `auto` channel, or a
  /// self-updating build with no download configured yet.
  final String? url;

  /// Whether the app should stop and insist.
  bool get isRequired => action == UpdateAction.required;

  /// Whether there is anything to offer at all.
  bool get isAvailable => action != UpdateAction.none;

  /// Whether the app itself has to fetch and install it. False for a shop
  /// build, which only has a link to open.
  bool get updatesItself => channel == UpdateChannel.self;

  @override
  String toString() => 'UpdatePlan(${action.wire} via ${channel.wire})';
}
