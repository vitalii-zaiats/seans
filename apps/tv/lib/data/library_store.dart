import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where somebody got to in something.
class WatchProgress {
  const WatchProgress({
    required this.slug,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.season,
    this.episode,
  });

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
    slug: json['slug']! as String,
    position: Duration(milliseconds: json['position']! as int),
    duration: Duration(milliseconds: json['duration']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt']! as int),
    season: json['season'] as int?,
    episode: json['episode'] as int?,
  );

  final String slug;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// Where in a series this was, when it is one.
  final int? season;
  final int? episode;

  /// 0–1. Zero when the duration is not known yet.
  double get fraction => duration.inMilliseconds == 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  /// Whether this is close enough to the end to count as watched.
  ///
  /// The last few minutes of a film are credits, so a stop there is a finish,
  /// not a pause — and "Continue watching" should not offer it back.
  bool get isFinished => fraction >= 0.94;

  /// Whether it is far enough in to be worth resuming at all.
  bool get isStarted => position.inSeconds > 60 && !isFinished;

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'season': season,
    'episode': episode,
  };
}

/// The two lists the API does not keep: what is half-watched, and what was
/// saved for later.
///
/// Backed by `shared_preferences`, which on Android is a single XML file — the
/// right size of storage for two lists of slugs on a box that has one user.
class LibraryStore {
  LibraryStore(this._prefs);

  static const _progressKey = 'watch.progress';
  static const _listKey = 'watch.list';

  /// How many half-watched titles are kept. The rail shows a handful; keeping
  /// the file unbounded would only make it slower to read at boot.
  static const _maxProgress = 20;

  static Future<LibraryStore> open() async =>
      LibraryStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Half-watched titles, most recent first, finished ones dropped.
  List<WatchProgress> continueWatching() {
    final raw = _prefs.getStringList(_progressKey) ?? const [];
    final entries = <WatchProgress>[];
    for (final line in raw) {
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          entries.add(WatchProgress.fromJson(json));
        }
      } on FormatException {
        // A row written by an older version of this app. Dropping it is
        // better than refusing to show the rail.
      }
    }
    return entries.where((entry) => entry.isStarted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Where somebody got to in [slug], if anywhere.
  WatchProgress? progressFor(String slug) {
    for (final entry in continueWatching()) {
      if (entry.slug == slug) return entry;
    }
    return null;
  }

  /// Records a position, replacing any earlier one for the same title.
  Future<void> saveProgress(WatchProgress progress) async {
    final kept = [
      progress,
      ...continueWatching().where((entry) => entry.slug != progress.slug),
    ].take(_maxProgress);

    await _prefs.setStringList(_progressKey, [
      for (final entry in kept) jsonEncode(entry.toJson()),
    ]);
  }

  /// Forgets a title — used when it finishes, and by "remove from the rail".
  Future<void> clearProgress(String slug) async {
    final kept = continueWatching().where((entry) => entry.slug != slug);
    await _prefs.setStringList(_progressKey, [
      for (final entry in kept) jsonEncode(entry.toJson()),
    ]);
  }

  /// Forgets everything: what was watched and what was saved.
  ///
  /// Part of the full reset in settings, which is the one place this is
  /// reachable from — nothing else has cause to erase somebody's history.
  Future<void> clear() async {
    await _prefs.remove(_progressKey);
    await _prefs.remove(_listKey);
  }

  /// Saved-for-later slugs, most recently added first.
  List<String> myList() => _prefs.getStringList(_listKey) ?? const [];

  bool isSaved(String slug) => myList().contains(slug);

  /// Adds or removes [slug], and reports which it did.
  Future<bool> toggleSaved(String slug) async {
    final current = myList();
    final saved = !current.contains(slug);
    await _prefs.setStringList(
      _listKey,
      saved
          ? [slug, ...current]
          : [
              for (final entry in current)
                if (entry != slug) entry,
            ],
    );
    return saved;
  }
}
