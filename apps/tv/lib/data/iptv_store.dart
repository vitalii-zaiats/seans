import 'package:flutter/foundation.dart';
import 'package:iptv/iptv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the owner keeps about live TV: which lists to load, what is starred,
/// and where they left off.
class IptvStore {
  IptvStore(this._prefs)
    : _favourites = ValueNotifier(
        (_prefs.getStringList(_favouritesKey) ?? const []).toSet(),
      );

  static const _favouritesKey = 'iptv.favourites';
  static const _lastKey = 'iptv.lastChannel';
  static const _sourcesKey = 'iptv.sources';
  static const _defaultsKey = 'iptv.defaults';

  static Future<IptvStore> open() async =>
      IptvStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final ValueNotifier<Set<String>> _favourites;

  /// Starred channels, by `LiveChannel.id`.
  ///
  /// Keyed on the id rather than the name: two lists spell the same channel
  /// three ways. For a playlist entry that id *is* its URL, which is what this
  /// held before sweet.tv existed — so nothing anybody starred was forgotten.
  Set<String> get favourites => _favourites.value;

  ValueListenable<Set<String>> get favouritesListenable => _favourites;

  void dispose() => _favourites.dispose();

  bool isFavourite(String id) => _favourites.value.contains(id);

  Future<bool> toggleFavourite(String id) async {
    final next = {..._favourites.value};
    final added = next.add(id);
    if (!added) next.remove(id);

    _favourites.value = next;
    await _prefs.setStringList(_favouritesKey, next.toList());
    return added;
  }

  /// The id of whatever was watched last, so the screen can open on it.
  String? get lastChannelId => _prefs.getString(_lastKey);

  Future<void> rememberChannel(String id) => _prefs.setString(_lastKey, id);

  /// Whether the built-in public lists are loaded at all.
  ///
  /// Somebody who only wants a curated source should not be handed a few
  /// hundred entries of somebody else's list, a good share of which are dead.
  /// Anything they added by hand stays either way — that was a deliberate act.
  bool get usesDefaults => _prefs.getBool(_defaultsKey) ?? true;

  Future<void> setUsesDefaults(bool value) =>
      _prefs.setBool(_defaultsKey, value);

  /// Playlists to load: the built-in ones plus anything the owner added.
  List<IptvSource> sources() {
    final custom = _prefs.getStringList(_sourcesKey) ?? const [];
    return [
      if (usesDefaults) ...IptvSource.defaults,
      for (final url in custom)
        IptvSource(id: url, title: _titleFor(url), url: url),
    ];
  }

  Future<void> addSource(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final custom = [..._prefs.getStringList(_sourcesKey) ?? const <String>[]];
    if (custom.contains(trimmed)) return;
    custom.add(trimmed);
    await _prefs.setStringList(_sourcesKey, custom);
  }

  Future<void> removeSource(String url) async {
    final custom = [
      for (final existing
          in _prefs.getStringList(_sourcesKey) ?? const <String>[])
        if (existing != url) existing,
    ];
    await _prefs.setStringList(_sourcesKey, custom);
  }

  Future<void> clear() async {
    _favourites.value = {};
    await _prefs.remove(_favouritesKey);
    await _prefs.remove(_lastKey);
    await _prefs.remove(_sourcesKey);
    await _prefs.remove(_defaultsKey);
  }

  /// A readable name for a URL somebody pasted — the file name, usually.
  static String _titleFor(String url) {
    final path = Uri.tryParse(url)?.pathSegments;
    if (path == null || path.isEmpty) return url;
    final name = path.last;
    return name.isEmpty ? url : name;
  }
}
