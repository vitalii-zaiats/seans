import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apps the owner wants one press away, in the order they pinned them.
///
/// A launcher whose other apps live behind a tab is a launcher you fight. This
/// is the row that fixes it.
class PinnedAppsStore {
  PinnedAppsStore(this._prefs)
    : _pinned = ValueNotifier(_prefs.getStringList(_key) ?? const []);

  static const _key = 'apps.pinned';

  /// How many fit on a row without the last one falling off the edge.
  static const max = 8;

  static Future<PinnedAppsStore> open() async =>
      PinnedAppsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final ValueNotifier<List<String>> _pinned;

  /// Package names, in pinned order.
  List<String> get packages => _pinned.value;

  ValueListenable<List<String>> get listenable => _pinned;

  void dispose() => _pinned.dispose();

  bool isPinned(String package) => _pinned.value.contains(package);

  bool get isFull => _pinned.value.length >= max;

  /// Pins or unpins, and says which it did.
  ///
  /// Returns `false` when a pin was refused for want of room — the caller can
  /// then say so rather than leaving somebody pressing a key that does
  /// nothing.
  Future<bool> toggle(String package) async {
    final pinned = isPinned(package);
    if (!pinned && isFull) return false;

    final next = pinned
        ? [
            for (final existing in _pinned.value)
              if (existing != package) existing,
          ]
        : [..._pinned.value, package];

    _pinned.value = next;
    await _prefs.setStringList(_key, next);
    return true;
  }

  Future<void> clear() async {
    _pinned.value = const [];
    await _prefs.remove(_key);
  }
}
