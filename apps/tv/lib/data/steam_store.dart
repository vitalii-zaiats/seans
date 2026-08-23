import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// What the box remembers about looking for Steam machines.
class SteamStore {
  SteamStore(this._prefs);

  static const _idKey = 'steam.clientId';
  static const _enabledKey = 'steam.enabled';

  static Future<SteamStore> open() async =>
      SteamStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// This box's id in Steam's eyes, made on first use and kept after.
  ///
  /// Steam tells devices apart by it, so a fresh one per scan would look like a
  /// new device every time somebody opened the screen. Stored as text because
  /// `SharedPreferences` has no unsigned 64-bit integer.
  int get clientId {
    final stored = int.tryParse(_prefs.getString(_idKey) ?? '');
    if (stored != null) return stored;

    // Positive and 63-bit: Dart has no unsigned int, and a negative value
    // would encode as a ten-byte varint that says something else entirely.
    final fresh =
        Random.secure().nextInt(1 << 32) << 16 |
        Random.secure().nextInt(1 << 16);
    _prefs.setString(_idKey, '$fresh');
    return fresh;
  }

  /// Whether to look for machines on the network at all.
  ///
  /// On by default — it is one broadcast datagram on the local network and
  /// nothing leaves it — but it is somebody's home network, so there is a
  /// switch.
  bool get enabled => _prefs.getBool(_enabledKey) ?? true;

  Future<void> setEnabled(bool value) => _prefs.setBool(_enabledKey, value);

  Future<void> clear() async {
    await _prefs.remove(_idKey);
    await _prefs.remove(_enabledKey);
  }
}
