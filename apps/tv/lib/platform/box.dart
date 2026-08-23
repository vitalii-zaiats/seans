import 'dart:async';

import 'package:flutter/services.dart';

/// One app installed on the box.
class InstalledApp {
  const InstalledApp({
    required this.package,
    required this.label,
    required this.leanback,
  });

  final String package;
  final String label;

  /// Whether the app files its entry under `LEANBACK_LAUNCHER` — i.e. it was
  /// written for a television rather than a phone.
  final bool leanback;

  @override
  bool operator ==(Object other) =>
      other is InstalledApp &&
      other.package == package &&
      other.label == label &&
      other.leanback == leanback;

  @override
  int get hashCode => Object.hash(package, label, leanback);
}

/// An app's artwork, already decoded to PNG bytes on the Android side.
class AppArt {
  const AppArt({required this.bytes, required this.banner});

  final Uint8List bytes;

  /// `true` for a 16:9 banner, `false` for a square-ish icon. The two want
  /// laying out differently.
  final bool banner;
}

/// One writable volume on the box.
class StorageVolume {
  const StorageVolume({
    required this.label,
    required this.path,
    required this.root,
    required this.removable,
    required this.totalBytes,
    required this.freeBytes,
  });

  /// What the system calls it — `Внутрішня пам'ять`, an SD card's own name.
  final String label;

  final String path;

  /// The drive's own root, where browsing it starts. [path] is this app's
  /// directory on the drive, which is not somewhere anybody wants to land.
  final String root;

  /// A card or a stick, as opposed to the box's built-in storage.
  final bool removable;

  final int totalBytes;
  final int freeBytes;

  int get usedBytes => totalBytes - freeBytes;

  /// 0–1. Zero when the volume did not report a size.
  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  /// Worth flagging: below this a download has nowhere to land.
  bool get isNearlyFull => totalBytes > 0 && usedFraction >= 0.92;

  @override
  bool operator ==(Object other) =>
      other is StorageVolume &&
      other.path == path &&
      other.totalBytes == totalBytes &&
      other.freeBytes == freeBytes;

  @override
  int get hashCode => Object.hash(path, totalBytes, freeBytes);
}

/// One entry in a directory on the box.
class BoxFile {
  const BoxFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.bytes,
    required this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;

  /// Meaningless for a directory, which is why the screen does not show it.
  final int bytes;

  final DateTime modified;

  /// Lower-case, without the dot. Empty when the name carries none.
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static const _video = {
    'mkv',
    'mp4',
    'avi',
    'mov',
    'm4v',
    'webm',
    'ts',
    'm2ts',
    'mpg',
    'mpeg',
    'wmv',
    'flv',
    '3gp',
  };
  static const _audio = {'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav'};

  /// Whether the launcher's own player can take it, rather than handing it to
  /// whatever else the box has — which on a bare box is nothing.
  bool get isPlayable =>
      _video.contains(extension) || _audio.contains(extension);

  bool get isVideo => _video.contains(extension);

  bool get isApk => extension == 'apk';
}

/// A drive, at its own root, for browsing.
class BoxRoot {
  const BoxRoot({
    required this.label,
    required this.path,
    required this.removable,
  });

  final String label;
  final String path;
  final bool removable;
}

/// One mode the panel accepts.
class DisplayMode {
  const DisplayMode({
    required this.id,
    required this.width,
    required this.height,
    required this.refreshRate,
    required this.active,
  });

  /// What [Box.preferMode] takes. Assigned by Android, not by us.
  final int id;

  final int width;
  final int height;
  final double refreshRate;

  /// Whether this is the one running now.
  final bool active;

  String get label =>
      '$width × $height · ${refreshRate.toStringAsFixed(refreshRate % 1 == 0 ? 0 : 2)} Гц';
}

/// What the panel is running at, and what the app is drawing into.
///
/// Two different numbers on purpose. A box can render at 1080p and hand that to
/// a 4K panel to upscale — from inside the app the two look identical, and the
/// only symptom is that everything is slightly soft.
class DisplayInfo {
  const DisplayInfo({
    required this.modeWidth,
    required this.modeHeight,
    required this.refreshRate,
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.densityDpi,
    required this.density,
    required this.modes,
    required this.preferredModeId,
  });

  /// The HDMI link: what the box sends to the panel.
  final int modeWidth;
  final int modeHeight;
  final double refreshRate;

  /// The surface Android gives the app, in real pixels.
  final int surfaceWidth;
  final int surfaceHeight;

  final int densityDpi;
  final double density;

  final List<DisplayMode> modes;

  /// What this window asked for, which is not always what it got — the system
  /// may refuse, and then this and the running mode disagree.
  final int preferredModeId;

  /// Whether something between the app and the panel is scaling the picture.
  ///
  /// This is the whole reason the screen exists: a launcher drawing 1080p onto
  /// a 4K panel looks blurred and has nothing on screen to say why.
  bool get isUpscaled =>
      surfaceWidth > 0 && modeWidth > 0 && surfaceWidth < modeWidth;

  /// A mode bigger than the one running, which the panel would accept.
  DisplayMode? get bestUnused {
    DisplayMode? best;
    for (final mode in modes) {
      if (mode.active || mode.width <= modeWidth) continue;
      if (best == null || mode.width > best.width) best = mode;
    }
    return best;
  }
}

/// Something the box said without being asked.
sealed class BoxEvent {
  const BoxEvent();
}

/// HOME was pressed while this launcher already was on screen.
class HomePressed extends BoxEvent {
  const HomePressed();
}

/// The set of installed apps changed.
class PackagesChanged extends BoxEvent {
  const PackagesChanged();
}

/// What the box is connected by: `ethernet`, `wifi`, `cellular` or `none`.
class LinkChanged extends BoxEvent {
  const LinkChanged(this.link);

  final String link;

  bool get isOffline => link == 'none';
}

/// Everything the launcher needs from the machine it runs on.
///
/// One seam, and the same idea as the transports in the packages: the screens
/// talk to this, and which platform is underneath is chosen once. Three
/// quarters of the app never touches it — home, catalogue, player, TV and
/// search know nothing about Android — and what does touch it is the part that
/// only exists on a set-top box.
///
/// A platform that cannot do something answers empty or `false` rather than
/// throwing. The interface has no way to say "not here", and it does not need
/// one: a list of installed apps that comes back empty hides its own row, and
/// a section with nothing in it hides its own tab. Absence is already how this
/// app expresses absence.
abstract interface class Box {
  /// Whether this machine has a launcher half at all.
  ///
  /// Synchronous, and the only member here that is: the interface decides what
  /// is on screen, and a tab cannot wait for a future to know whether to
  /// exist. Everything behind it — the installed apps, the drives, the network
  /// glyph, a scan of the local network — is a set-top box's own hardware and
  /// software, and on a machine without them the honest answer is not an empty
  /// list but no section.
  bool get present;

  /// Who installed this copy of the app.
  ///
  /// `com.android.vending` when it came from Google Play, some other package
  /// when it came from another shop, `null` for a sideload — and `null`
  /// everywhere that is not Android, which is the honest answer rather than a
  /// missing one: a browser has no installer.
  ///
  /// It decides two things on the server, and neither is cosmetic: where an
  /// update comes from, and which sections this build may show at all.
  Future<String?> installer();

  /// Everything with a way in, by label, this launcher excepted.
  Future<List<InstalledApp>> apps();

  /// One app's banner or icon. `null` when it has neither.
  Future<AppArt?> art(String package);

  /// Starts an app. `false` when there was nothing to start.
  Future<bool> launch(String package);

  /// Opens the machine's own settings.
  Future<bool> settings();

  /// The volumes this machine can write to, with how full each one is.
  Future<List<StorageVolume>> storage();

  /// Opens the system's Wi-Fi picker.
  Future<bool> wifi();

  /// The processor architectures this machine runs, best first.
  Future<List<String>> abis();

  /// A directory a download may land in.
  Future<String> stagingDir();

  /// Whether the owner has allowed this launcher to offer apps for install.
  Future<bool> canInstall();

  /// Opens the settings screen that grants it.
  Future<bool> requestInstall();

  /// Hands a downloaded package to the system installer.
  Future<bool> install(String path);

  /// Throws away everything staged for install.
  Future<void> clearStaging();

  /// Whether this app may read the drives.
  Future<bool> canReadFiles();

  Future<bool> requestReadFiles();

  /// The drives, each at its own root.
  Future<List<BoxRoot>> roots();

  /// One directory, folders first and then by name.
  Future<List<BoxFile>> listDir(String path);

  /// Hands a file to whatever claims to open its kind.
  Future<bool> openFile(String path);

  /// Opens an app's page in whatever store there is.
  Future<bool> store(String package);

  /// Opens a page full screen, in a window of its own.
  Future<bool> openWeb(String url, {String? agent});

  /// What the panel is running at. `null` when the machine did not say.
  Future<DisplayInfo?> display();

  /// Asks the system for a display mode. `0` hands the choice back.
  Future<bool> preferMode(int modeId);

  /// Holds the lock that lets broadcast datagrams reach this app.
  Future<bool> holdMulticast();

  Future<bool> releaseMulticast();

  /// What the machine says without being asked. Never closes.
  Stream<BoxEvent> events();
}
