import '../json.dart';

/// What a television is handed when it asks a phone to sign it in.
final class DeviceLink {
  const DeviceLink({
    required this.code,
    required this.secret,
    required this.verifyPath,
    required this.expiresIn,
  });

  factory DeviceLink.fromJson(JsonMap json) {
    const owner = 'DeviceLink';
    return DeviceLink(
      code: json.requireString('code', owner: owner),
      secret: json.requireString('secret', owner: owner),
      verifyPath: json.requireString('verify_path', owner: owner),
      expiresIn: json.requireInt('expires_in', owner: owner),
    );
  }

  /// Short, and read off a screen: no `O/0` or `I/1` in the alphabet that makes
  /// it. Goes on the screen and into the QR. Knowing it only lets somebody
  /// *approve* — it collects nothing.
  final String code;

  /// **Never leaves this device.** The only thing that can collect the session,
  /// which is what makes an approval given to the wrong person harmless.
  final String secret;

  /// Where the phone should go, as a path. The server does not know what
  /// address it is reached on; whatever draws the QR does.
  final String verifyPath;

  /// Seconds left. Long enough to find a phone, short enough that a code left
  /// on a screen in a shared flat goes stale on its own.
  final int expiresIn;

  /// The URL to put in the QR, given wherever the web app lives.
  Uri verifyUrl(Uri webBase) => webBase.resolve(verifyPath);

  @override
  String toString() => 'DeviceLink($code, ${expiresIn}s left)';
}

/// What the phone is about to approve, before it approves it.
final class DeviceLinkStatus {
  const DeviceLinkStatus({
    required this.code,
    required this.approved,
    required this.expiresIn,
    this.deviceName,
  });

  factory DeviceLinkStatus.fromJson(JsonMap json) {
    const owner = 'DeviceLinkStatus';
    return DeviceLinkStatus(
      code: json.requireString('code', owner: owner),
      approved: json.boolOr('approved'),
      expiresIn: json.requireInt('expires_in', owner: owner),
      deviceName: json.stringOrNull('device_name'),
    );
  }

  final String code;

  /// What to tell the person before they say yes. "Android TV", "macOS" — not
  /// proof of anything, but it is the difference between approving your own
  /// living room and approving somebody else's.
  final String? deviceName;

  final bool approved;
  final int expiresIn;

  bool get hasExpired => expiresIn <= 0;

  @override
  String toString() =>
      'DeviceLinkStatus($code, ${approved ? 'approved' : 'pending'})';
}
