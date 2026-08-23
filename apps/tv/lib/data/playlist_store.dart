import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A named list of titles.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    required this.slugs,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id']! as String,
    title: json['title']! as String,
    slugs: [
      for (final slug in (json['slugs'] as List? ?? const []))
        if (slug is String) slug,
    ],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      json['updatedAt'] as int? ?? 0,
    ),
  );

  final String id;
  final String title;

  /// Content slugs, most recently added first.
  final List<String> slugs;

  final DateTime updatedAt;

  bool get isEmpty => slugs.isEmpty;
  int get length => slugs.length;

  bool contains(String slug) => slugs.contains(slug);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'slugs': slugs,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  Playlist copyWith({
    String? title,
    List<String>? slugs,
    DateTime? updatedAt,
  }) => Playlist(
    id: id,
    title: title ?? this.title,
    slugs: slugs ?? this.slugs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Playlists the owner made, kept on the box.
///
/// Public collections — a top-rated list and the like — will come from the
/// server; see [PublicPlaylists]. Nothing here reaches the network.
class PlaylistStore {
  PlaylistStore(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _notifier = ValueNotifier(_read(_prefs));

  static const _key = 'playlists';

  static Future<PlaylistStore> open() async =>
      PlaylistStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final ValueNotifier<List<Playlist>> _notifier;

  /// Every playlist, most recently touched first.
  List<Playlist> get all => _notifier.value;

  /// Fires on any change, so a screen showing them can redraw.
  ///
  /// A separate listenable rather than the store itself: `RepositoryProvider`
  /// hands this around and refuses a `Listenable`.
  ValueListenable<List<Playlist>> get listenable => _notifier;

  void dispose() => _notifier.dispose();

  static List<Playlist> _read(SharedPreferences prefs) {
    final raw = prefs.getStringList(_key) ?? const [];
    final playlists = <Playlist>[];
    for (final line in raw) {
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          playlists.add(Playlist.fromJson(json));
        }
      } on FormatException {
        // A row written by an older build. Dropping it beats refusing to show
        // the rest.
      }
    }
    return playlists..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Playlist? byId(String id) {
    for (final playlist in all) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  /// Which of the owner's playlists already hold [slug].
  List<Playlist> holding(String slug) => [
    for (final playlist in all)
      if (playlist.contains(slug)) playlist,
  ];

  Future<Playlist> create(String title) async {
    final trimmed = title.trim();
    final playlist = Playlist(
      // Wall-clock microseconds: one box, one person, no chance of a clash
      // that a heavier id scheme would be buying insurance against.
      id: 'pl_${_now().microsecondsSinceEpoch}',
      title: trimmed.isEmpty ? 'Без назви' : trimmed,
      slugs: const [],
      updatedAt: _now(),
    );
    await _write([playlist, ...all]);
    return playlist;
  }

  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await _update(id, (playlist) => playlist.copyWith(title: trimmed));
  }

  Future<void> remove(String id) async {
    await _write([
      for (final playlist in all)
        if (playlist.id != id) playlist,
    ]);
  }

  /// Adds [slug] if missing, removes it if present, and says which it did.
  Future<bool> toggle(String id, String slug) async {
    final playlist = byId(id);
    if (playlist == null) return false;

    final holds = playlist.contains(slug);
    await _update(
      id,
      (current) => current.copyWith(
        slugs: holds
            ? [
                for (final existing in current.slugs)
                  if (existing != slug) existing,
              ]
            : [slug, ...current.slugs],
      ),
    );
    return !holds;
  }

  /// Drops every playlist the owner made.
  Future<void> clear() async {
    _notifier.value = const [];
    await _prefs.remove(_key);
  }

  Future<void> _update(String id, Playlist Function(Playlist) change) async {
    await _write([
      for (final playlist in all)
        if (playlist.id == id)
          change(playlist).copyWith(updatedAt: _now())
        else
          playlist,
    ]);
  }

  Future<void> _write(List<Playlist> playlists) async {
    final sorted = [...playlists]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _notifier.value = sorted;
    await _prefs.setStringList(_key, [
      for (final playlist in sorted) jsonEncode(playlist.toJson()),
    ]);
  }
}

/// Collections the server curates — a top-rated list, a staff pick, whatever
/// the catalogue decides to publish.
///
/// There is no endpoint for these yet. The interface exists so the screen can
/// be built against it and the implementation dropped in without touching the
/// UI; until then [PublicPlaylists.unavailable] is what the app is wired with,
/// and the screen says plainly that there is nothing to show rather than
/// inventing a list.
abstract interface class PublicPlaylists {
  /// Whether the catalogue offers these at all.
  bool get isAvailable;

  /// The published collections, newest first.
  Future<List<Playlist>> featured();

  /// A stand-in until the endpoint exists.
  static const PublicPlaylists unavailable = _NoPublicPlaylists();
}

class _NoPublicPlaylists implements PublicPlaylists {
  const _NoPublicPlaylists();

  @override
  bool get isAvailable => false;

  @override
  Future<List<Playlist>> featured() async => const [];
}
