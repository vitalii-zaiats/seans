import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The identifier this copy of the app announces itself by.
///
/// Made once and kept, which is the whole point: it is what lets a guest
/// account survive a restart. A fresh one per launch would look to the server
/// like a new box every time, and nothing anybody watched would follow them.
///
/// It is not a credential. Anybody can send any uuid; what authenticates a
/// later call is the session token the server hands back for it.
///
/// Clearing it is how somebody asks to be forgotten — the server writes nothing
/// down for a launch that sends no id at all, so the next start is a first one.
class InstallStore {
  InstallStore(this._prefs);

  static const _idKey = 'install.id';

  static Future<InstallStore> open() async =>
      InstallStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// The stored id, or `null` when this box has chosen to stay anonymous.
  String? get id => _prefs.getString(_idKey);

  /// The stored id, making one on first use.
  Future<String> ensure() async {
    final stored = id;
    if (stored != null && stored.isNotEmpty) return stored;

    final fresh = _uuid();
    await _prefs.setString(_idKey, fresh);
    return fresh;
  }

  /// Stop being remembered. The next launch announces nothing.
  Future<void> forget() => _prefs.remove(_idKey);

  /// A version-4 uuid.
  ///
  /// Hand-rolled rather than pulled in: this is the only place in the app that
  /// needs one, and it needs to be unique on this box rather than unguessable.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
