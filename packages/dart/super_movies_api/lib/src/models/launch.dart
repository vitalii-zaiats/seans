import '../json.dart';

/// Where the app is running.
///
/// Named `AppPlatform` rather than `Platform` so it does not collide with
/// `dart:io`, which every non-web build imports.
enum AppPlatform {
  android('android'),
  linux('linux'),
  windows('windows'),
  web('web');

  const AppPlatform(this.wire);

  /// The value the API expects in `platform`.
  final String wire;

  /// The matching platform, or `null` for anything unrecognised. Never throws:
  /// an API that grows a fifth platform must not break parsing of the four
  /// known ones.
  static AppPlatform? tryParse(String? wire) {
    for (final platform in values) {
      if (platform.wire == wire) return platform;
    }
    return null;
  }

  @override
  String toString() => wire;
}

/// The installer package Google Play reports on an Android install.
///
/// Worth a constant because the whole update story turns on it: a build that
/// came from the shop must be sent back to the shop, never sideload its own
/// APK, and gets fewer features switched on.
const String playStore = 'com.android.vending';

/// What the app says about itself at start-up.
///
/// Two ways to build one, and they are the first two of the three account
/// modes:
///
/// * [Launch.anonymous] sends no identifier. Nothing about the launch is
///   written down server-side — no install row, no account, no session — and
///   the answer carries only the update plan and the feature flags.
/// * [Launch.identified] sends the uuid the app generated and kept. That is
///   what makes a guest possible: history follows the token handed back.
///
/// The third mode, a claimed account, is not a different launch — it is the
/// same identified one, with a token already in hand.
final class Launch {
  /// Tell the server nothing it could remember this box by.
  const Launch.anonymous({
    required this.platform,
    required this.version,
    this.vendor,
  }) : installId = null;

  /// Announce this installation, so it can carry an account.
  const Launch.identified({
    required String this.installId,
    required this.platform,
    required this.version,
    this.vendor,
  });

  /// A uuid the client generated once and kept. `null` in anonymous mode.
  final String? installId;

  final AppPlatform platform;

  /// The installer package — [playStore] and friends. Android only: the API
  /// refuses it from anywhere else rather than ignoring it, because outside
  /// android there is no installer to report.
  final String? vendor;

  /// `1.4.2` or `1.4.2+37`.
  final String version;

  /// Whether the shop installed this build, which decides where an update comes
  /// from and how much the build is allowed to switch on.
  bool get isFromPlayStore => vendor == playStore;

  JsonMap toJson() => {
    if (installId != null) 'id': installId,
    'platform': platform.wire,
    if (vendor != null) 'vendor': vendor,
    'ver': version,
  };

  @override
  String toString() =>
      'Launch(${installId ?? 'anonymous'}, $platform, $version)';
}
