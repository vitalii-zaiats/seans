import 'dart:async';

import 'package:flutter/services.dart';

import 'box.dart';

/// The Android half of the launcher.
///
/// The only implementation that answers anything: a set-top box is where the
/// installed apps, the storage volumes, the package installer and the HDMI
/// mode all live.
class AndroidBox implements Box {
  const AndroidBox();

  @override
  bool get present => true;

  static const _calls = MethodChannel('tv.seans/launcher');
  static const _events = EventChannel('tv.seans/launcher/events');

  /// Who installed this copy — `com.android.vending` when it came from Play.
  ///
  /// `null` for a sideload, which Android reports as no installer at all. The
  /// server treats that as "updates itself", which is exactly right: nobody
  /// else is going to update an APK somebody copied onto the box.
  @override
  Future<String?> installer() async => _calls.invokeMethod<String>('installer');

  /// Everything with a way in, by label, this launcher excepted.
  @override
  Future<List<InstalledApp>> apps() async {
    final raw = await _calls.invokeListMethod<Object?>('apps') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          InstalledApp(
            package: entry['package']! as String,
            label: entry['label']! as String,
            leanback: entry['leanback'] as bool? ?? false,
          ),
    ];
  }

  /// One app's banner or icon. `null` when it has neither.
  @override
  Future<AppArt?> art(String package) async {
    final raw = await _calls.invokeMapMethod<String, Object?>('art', package);
    final bytes = raw?['bytes'];
    if (bytes is! Uint8List) return null;
    return AppArt(bytes: bytes, banner: raw?['banner'] as bool? ?? false);
  }

  /// Starts an app. `false` when there was nothing to start.
  @override
  Future<bool> launch(String package) async =>
      await _calls.invokeMethod<bool>('launch', package) ?? false;

  /// Opens the box's own settings — inputs, network, storage.
  @override
  Future<bool> settings() async =>
      await _calls.invokeMethod<bool>('settings') ?? false;

  /// The volumes this box can write to, with how full each one is.
  @override
  Future<List<StorageVolume>> storage() async {
    final raw = await _calls.invokeListMethod<Object?>('storage') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          StorageVolume(
            label: entry['label']! as String,
            path: entry['path']! as String,
            root: entry['root'] as String? ?? entry['path']! as String,
            removable: entry['removable'] as bool? ?? false,
            totalBytes: entry['total'] as int? ?? 0,
            freeBytes: entry['free'] as int? ?? 0,
          ),
    ];
  }

  /// Opens the system's Wi-Fi picker.
  ///
  /// Not a list this app draws: since Android 10 a third-party app cannot join
  /// the *system* to a network, so a self-drawn list would be one nothing on
  /// it works from. On Android 10 and up this slides a panel over the app; on
  /// a box without one it falls back to the Wi-Fi settings screen.
  @override
  Future<bool> wifi() async => await _calls.invokeMethod<bool>('wifi') ?? false;

  /// The processor architectures this box runs, best first.
  ///
  /// F-Droid builds an APK per architecture, so this is what decides which
  /// download is the right one. An empty list means the box did not say, and
  /// the caller should not guess.
  @override
  Future<List<String>> abis() async =>
      await _calls.invokeListMethod<String>('abis') ?? const [];

  /// The directory a download may land in — inside the app's own cache.
  @override
  Future<String> stagingDir() async =>
      await _calls.invokeMethod<String>('stagingDir') ?? '';

  /// Whether the owner has allowed this launcher to offer apps for install.
  @override
  Future<bool> canInstall() async =>
      await _calls.invokeMethod<bool>('canInstall') ?? false;

  /// Opens the settings screen that grants it.
  @override
  Future<bool> requestInstall() async =>
      await _calls.invokeMethod<bool>('requestInstall') ?? false;

  /// Hands a downloaded APK to the system installer, which asks the owner.
  ///
  /// Not a silent install — that needs Device Owner, and a factory-fresh box
  /// to set it on. The confirmation is the point.
  @override
  Future<bool> install(String path) async =>
      await _calls.invokeMethod<bool>('install', path) ?? false;

  /// Throws away everything staged for install.
  @override
  Future<void> clearStaging() => _calls.invokeMethod<bool>('clearStaging');

  /// Whether this app may read the drives.
  ///
  /// From Android 11 this is *All files access*, which has no dialog — only a
  /// settings screen. [requestReadFiles] opens it.
  @override
  Future<bool> canReadFiles() async =>
      await _calls.invokeMethod<bool>('canReadFiles') ?? false;

  @override
  Future<bool> requestReadFiles() async =>
      await _calls.invokeMethod<bool>('requestReadFiles') ?? false;

  /// The drives, each at its own root — where browsing starts.
  @override
  Future<List<BoxRoot>> roots() async {
    final raw = await _calls.invokeListMethod<Object?>('roots') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          BoxRoot(
            label: entry['label']! as String,
            path: entry['path']! as String,
            removable: entry['removable'] as bool? ?? false,
          ),
    ];
  }

  /// One directory, folders first and then by name — sorted on the Android
  /// side, where the names actually live.
  @override
  Future<List<BoxFile>> listDir(String path) async {
    final raw =
        await _calls.invokeListMethod<Object?>('listDir', path) ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          BoxFile(
            name: entry['name']! as String,
            path: entry['path']! as String,
            isDirectory: entry['dir'] as bool? ?? false,
            bytes: entry['size'] as int? ?? 0,
            modified: DateTime.fromMillisecondsSinceEpoch(
              entry['modified'] as int? ?? 0,
            ),
          ),
    ];
  }

  /// Hands a file to whatever on the box claims to open its kind.
  @override
  Future<bool> openFile(String path) async =>
      await _calls.invokeMethod<bool>('openFile', path) ?? false;

  /// What the panel is running at. `null` when the box did not say.
  @override
  Future<DisplayInfo?> display() async {
    final raw = await _calls.invokeMapMethod<String, Object?>('screen');
    if (raw == null || raw.isEmpty) return null;

    return DisplayInfo(
      modeWidth: raw['modeWidth'] as int? ?? 0,
      modeHeight: raw['modeHeight'] as int? ?? 0,
      refreshRate: (raw['refreshRate'] as num?)?.toDouble() ?? 0,
      surfaceWidth: raw['surfaceWidth'] as int? ?? 0,
      surfaceHeight: raw['surfaceHeight'] as int? ?? 0,
      densityDpi: raw['densityDpi'] as int? ?? 0,
      density: (raw['density'] as num?)?.toDouble() ?? 0,
      preferredModeId: raw['preferredModeId'] as int? ?? 0,
      modes: [
        for (final entry in raw['modes'] as List? ?? const [])
          if (entry is Map)
            DisplayMode(
              id: entry['id'] as int? ?? 0,
              width: entry['width'] as int? ?? 0,
              height: entry['height'] as int? ?? 0,
              refreshRate: (entry['refreshRate'] as num?)?.toDouble() ?? 0,
              active: entry['active'] as bool? ?? false,
            ),
      ],
    );
  }

  /// Asks the system for a display mode. `0` hands the choice back.
  ///
  /// A request, not a command — the documented, permission-free way to change
  /// what the box outputs, and the system is free to refuse it.
  @override
  Future<bool> preferMode(int modeId) async =>
      await _calls.invokeMethod<bool>('preferMode', modeId) ?? false;

  /// Opens an app's page in the box's store.
  ///
  /// For apps this launcher cannot fetch itself — Steam Link is on Play and
  /// nowhere else, so the F-Droid path is no help there.
  @override
  Future<bool> store(String package) async =>
      await _calls.invokeMethod<bool>('store', package) ?? false;

  /// Opens a page full screen, in a window of its own.
  ///
  /// Not a WebView inside the Flutter tree: embedded as a platform view, the
  /// arrow keys never reach the page — Flutter's focus traversal takes them
  /// first and walks the widget tree instead. Its own activity gets the key
  /// events the way a browser does, so the page's own navigation works and a
  /// gamepad reaches it.
  ///
  /// [agent] is what the page is told it is talking to. The sites worth opening
  /// this way refuse anything that looks like a television.
  @override
  Future<bool> openWeb(String url, {String? agent}) async =>
      await _calls.invokeMethod<bool>('openWeb', {
        'url': url,
        'agent': agent,
      }) ??
      false;

  /// Holds the lock that lets broadcast datagrams reach this app.
  ///
  /// Only for the length of a scan. Without it discovery is silent on Wi-Fi and
  /// works over Ethernet — a difference that reads as a protocol bug.
  @override
  Future<bool> holdMulticast() async =>
      await _calls.invokeMethod<bool>('holdMulticast') ?? false;

  @override
  Future<bool> releaseMulticast() async =>
      await _calls.invokeMethod<bool>('releaseMulticast') ?? false;

  /// HOME presses, package changes and network changes, as one stream.
  @override
  Stream<BoxEvent> events() => _events
      .receiveBroadcastStream()
      .map<BoxEvent?>((raw) {
        if (raw is! Map) return null;
        return switch (raw['kind']) {
          'home' => const HomePressed(),
          'packages' => const PackagesChanged(),
          'link' => LinkChanged(raw['link'] as String? ?? 'none'),
          _ => null,
        };
      })
      .where((event) => event != null)
      .cast<BoxEvent>();
}
