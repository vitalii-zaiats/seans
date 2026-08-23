import 'package:shared_preferences/shared_preferences.dart';

/// Whether the owner wants sweet.tv's free channels at all.
///
/// Nothing else. The identity that used to live here — a uuid this box invented
/// and kept, standing in for an account there is none of — moved to the API
/// when the service did: the box no longer talks to sweet.tv, and one identity
/// per box was never what that service should have been told anyway.
class SweetTvStore {
  SweetTvStore(this._prefs);

  static const _enabledKey = 'sweet.enabled';

  static Future<SweetTvStore> open() async =>
      SweetTvStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// On by default: it is a free list that needs no setting up, and a source
  /// nobody knows to switch on is a source nobody uses.
  bool get enabled => _prefs.getBool(_enabledKey) ?? true;

  Future<void> setEnabled(bool value) => _prefs.setBool(_enabledKey, value);

  Future<void> clear() => _prefs.remove(_enabledKey);
}
