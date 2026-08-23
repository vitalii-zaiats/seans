/// One playable stream URL, with whatever label the page gave it.
class AshdiStream {
  const AshdiStream({required this.url, this.label, this.source = 'playerjs'});

  final String url;

  /// The player's own words for this stream — a quality tag, a dub name, or
  /// the whole playlist path (`Postmodern / Сезон 1 / Серія 1`).
  final String? label;

  /// How it was found: `playerjs` from the player config, `page-scan` when the
  /// config could not be read and the page was swept for URLs instead.
  final String source;

  @override
  bool operator ==(Object other) =>
      other is AshdiStream &&
      other.url == url &&
      other.label == label &&
      other.source == source;

  @override
  int get hashCode => Object.hash(url, label, source);

  @override
  String toString() => 'AshdiStream(${label ?? '—'} -> $url)';
}

/// One `.vtt` track an episode ships with, labelled in the player's words.
class AshdiSubtitle {
  const AshdiSubtitle({required this.url, this.label});

  final String url;
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is AshdiSubtitle && other.url == url && other.label == label;

  @override
  int get hashCode => Object.hash(url, label);

  @override
  String toString() => 'AshdiSubtitle(${label ?? '—'})';
}

/// One leaf of a serial's playlist: where it sits, and what it plays.
///
/// [season] and [episode] are what the playlist titles said — `null` when they
/// said nothing, which is honest about a playlist whose folders were named
/// freely.
class AshdiEpisode {
  const AshdiEpisode({
    this.title = '',
    this.season,
    this.episode,
    this.episodeEnd,
    this.dub,
    this.streams = const [],
    this.subtitles = const [],
    this.poster,
    this.videoId,
    this.folders = const [],
  });

  final String title;
  final int? season;
  final int? episode;

  /// A pair aired as one file: `Серія 12-13`.
  final int? episodeEnd;

  /// The folder above the seasons — a dub studio, or `Субтитри`.
  final String? dub;

  final List<AshdiStream> streams;
  final List<AshdiSubtitle> subtitles;
  final String? poster;
  final String? videoId;

  /// Every folder title above this leaf, outermost first.
  final List<String> folders;

  /// What to play when nobody asked for a particular quality.
  String? get url => streams.isEmpty ? null : streams.first.url;

  @override
  String toString() =>
      'AshdiEpisode(s${season ?? '?'}e${episode ?? '?'}${dub == null ? '' : ', $dub'})';
}

/// Everything one player page turned out to hold.
class AshdiPlayer {
  const AshdiPlayer({
    required this.url,
    this.streams = const [],
    this.episodes = const [],
  });

  /// The player page this came from.
  final String url;

  /// Every distinct stream on the page, in document order. For a serial this
  /// is every episode's streams flattened.
  final List<AshdiStream> streams;

  /// The playlist, when the page had one. Empty for a film.
  final List<AshdiEpisode> episodes;

  bool get isSerial => episodes.isNotEmpty;

  /// The stream to play when nothing more specific was asked for.
  String? get firstUrl => streams.isEmpty ? null : streams.first.url;

  @override
  String toString() =>
      'AshdiPlayer($url, ${streams.length} streams, ${episodes.length} episodes)';
}
