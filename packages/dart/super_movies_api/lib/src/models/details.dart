import '../json.dart';
import 'catalogue.dart';

/// One playable stream offered by a hosting provider.
///
/// A season can list several for the same provider — usually different dubs,
/// told apart by [name].
final class PlayerSource {
  const PlayerSource({required this.name, required this.link});

  factory PlayerSource.fromJson(JsonMap json) => PlayerSource(
    name: json.stringOrNull('name') ?? '',
    link: json.requireString('link', owner: 'PlayerSource'),
  );

  /// Label of the dub or release group, e.g. `DniproFilm`.
  final String name;

  /// An embeddable player URL on the provider's own domain.
  final String link;

  @override
  bool operator ==(Object other) =>
      other is PlayerSource && other.name == name && other.link == link;

  @override
  int get hashCode => Object.hash(name, link);

  @override
  String toString() => 'PlayerSource($name -> $link)';
}

/// A still or backdrop attached to a season.
final class SeasonFrame {
  const SeasonFrame({
    required this.url,
    required this.source,
    required this.position,
    this.episodeNumber,
  });

  factory SeasonFrame.fromJson(JsonMap json) => SeasonFrame(
    url: json.requireString('url', owner: 'SeasonFrame'),
    source: json.stringOrNull('source') ?? '',
    position: json.intOr('position'),
    episodeNumber: json.intOrNull('episode_number'),
  );

  final String url;

  /// Where it came from. Only `backdrop` appears in captured traffic.
  final String source;

  /// Sort order within the season's frames.
  final int position;

  /// The episode it belongs to, when it is a still rather than a season-wide
  /// backdrop.
  final int? episodeNumber;

  @override
  String toString() => 'SeasonFrame($url)';
}

/// One episode of a season.
final class Episode {
  const Episode({
    required this.number,
    this.name,
    this.airDate,
    this.ready = false,
  });

  factory Episode.fromJson(JsonMap json) => Episode(
    number: json.requireInt('number', owner: 'Episode'),
    name: json.stringOrNull('name'),
    airDate: json.dateTimeOrNull('air_date'),
    ready: json.boolOr('ready'),
  );

  /// 1-based, and the key into the season's player map.
  final int number;

  final String? name;
  final DateTime? airDate;

  /// Whether it is published. An unreleased episode is still listed, with
  /// nothing behind it.
  final bool ready;

  @override
  bool operator ==(Object other) =>
      other is Episode && other.number == number && other.name == name;

  @override
  int get hashCode => Object.hash(number, name);

  @override
  String toString() => 'Episode($number${ready ? '' : ', unreleased'})';
}

/// A person credited on a title — an entry of `cast` or `directors`.
final class Credit {
  const Credit({
    required this.name,
    required this.originalName,
    required this.slug,
    required this.gender,
    this.character,
    this.posterUrl,
  });

  factory Credit.fromJson(JsonMap json) {
    const owner = 'Credit';
    return Credit(
      name: json.requireString('name', owner: owner),
      originalName: json.requireString('original_name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      gender: Gender.fromCode(json.intOrNull('gender')),
      character: json.stringOrNull('character'),
      posterUrl: json.stringOrNull('poster_url'),
    );
  }

  final String name;
  final String originalName;
  final String slug;
  final Gender gender;

  /// The role played. Always `null` for a director.
  final String? character;

  final String? posterUrl;

  @override
  String toString() =>
      character == null ? 'Credit($slug)' : 'Credit($slug as $character)';
}

/// One entry in a franchise's ordered list of titles.
final class FranchiseItem {
  const FranchiseItem({
    required this.name,
    required this.originalName,
    required this.slug,
    required this.format,
    required this.isCurrent,
    this.year,
    this.imdbMark,
    this.posterUrl,
    this.seasonNumber,
  });

  factory FranchiseItem.fromJson(JsonMap json) {
    const owner = 'FranchiseItem';
    return FranchiseItem(
      name: json.requireString('name', owner: owner),
      originalName: json.requireString('original_name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      format: json.stringOrNull('format') ?? '',
      isCurrent: json.boolOr('is_current'),
      year: json.intOrNull('year'),
      imdbMark: json.doubleOrNull('imdb_mark'),
      posterUrl: json.stringOrNull('poster_url'),
      seasonNumber: json.intOrNull('season_number'),
    );
  }

  final String name;
  final String originalName;
  final String slug;
  final String format;

  /// True for the title whose page you are looking at.
  final bool isCurrent;

  final int? year;
  final double? imdbMark;
  final String? posterUrl;

  /// Set when the entry is a specific season rather than a whole title.
  final int? seasonNumber;

  @override
  String toString() => 'FranchiseItem($slug${isCurrent ? ', current' : ''})';
}

/// A collection a title belongs to, with its siblings.
final class Franchise {
  const Franchise({
    required this.name,
    required this.slug,
    required this.items,
    this.description,
  });

  factory Franchise.fromJson(JsonMap json) {
    const owner = 'Franchise';
    return Franchise(
      name: json.requireString('name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      items: json.listOf('items', FranchiseItem.fromJson),
      description: json.stringOrNull('description'),
    );
  }

  final String name;
  final String slug;
  final List<FranchiseItem> items;
  final String? description;

  /// The entry marked current, if upstream flagged one.
  FranchiseItem? get current {
    for (final item in items) {
      if (item.isCurrent) return item;
    }
    return null;
  }

  @override
  String toString() => 'Franchise($slug, ${items.length} items)';
}

/// A season of a series, or the single pseudo-season a film is wrapped in.
///
/// Upstream ships streams in two shapes under one key: a film's map is keyed by
/// provider, a series' by episode number with providers one level in. The API
/// hands them over as two fields rather than one, and both reach callers
/// through the same [sourcesFor] / [availablePlayers] pair.
final class Season {
  const Season({
    required this.id,
    required this.number,
    required this.description,
    required this.shortDescription,
    required this.frames,
    required this.playerData,
    required this.episodePlayers,
    required this.players,
    required this.rightsBlocked,
    required this.readyEpisodesCount,
    required this.episodes,
    this.releaseDate,
    this.posterUrl,
    this.trailerYoutubeId,
    this.lastReadyEpisode,
    this.lastUrlSuffix,
  });

  factory Season.fromJson(JsonMap json) {
    const owner = 'Season';
    return Season(
      id: json.requireInt('id', owner: owner),
      number: json.requireInt('number', owner: owner),
      description: json.stringOrNull('description') ?? '',
      shortDescription: json.stringOrNull('short_description') ?? '',
      frames: json.listOf('frames', SeasonFrame.fromJson),
      playerData: _providers(json.mapOrNull('player_data')),
      episodePlayers: _episodes(json.mapOrNull('episode_players')),
      players: (json['players'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      rightsBlocked: json.boolOr('rights_blocked'),
      readyEpisodesCount: json.intOr('ready_episodes_count'),
      episodes: json.listOf('episodes', Episode.fromJson),
      releaseDate: json.dateTimeOrNull('release_date'),
      posterUrl: json.stringOrNull('poster_url'),
      trailerYoutubeId: json.stringOrNull('trailer_youtube_id'),
      lastReadyEpisode: json.intOrNull('last_ready_episode'),
      lastUrlSuffix: json.stringOrNull('last_url_suffix'),
    );
  }

  final int id;

  /// 1-based. A film exposes a single season numbered `1`.
  final int number;

  final String description;
  final String shortDescription;

  /// Backdrops and episode stills.
  final List<SeasonFrame> frames;

  /// Streams by provider, for a film-shaped season. Empty for a series.
  final Map<String, List<PlayerSource>> playerData;

  /// Streams by episode number and then by provider. Empty for a film.
  final Map<int, Map<String, List<PlayerSource>>> episodePlayers;

  /// Provider keys the site is willing to show, in display order. One listed
  /// here may carry no stream — [availablePlayers] is what really plays.
  final List<String> players;

  /// Playback withheld for rights reasons.
  final bool rightsBlocked;

  /// Empty for a film, and for a season upstream has not filled in.
  final List<Episode> episodes;

  final int readyEpisodesCount;
  final DateTime? releaseDate;
  final String? posterUrl;
  final String? trailerYoutubeId;
  final int? lastReadyEpisode;
  final String? lastUrlSuffix;

  /// Whether upstream actually filled this season in.
  ///
  /// A series returns every season it ever had but the episodes and players of
  /// only one; the rest arrive with nothing in them — which reads exactly like
  /// a season with nothing to watch, and is not the same thing at all. Ask for
  /// the season by number to fill it.
  bool get isLoaded =>
      players.isNotEmpty ||
      episodes.isNotEmpty ||
      playerData.isNotEmpty ||
      episodePlayers.isNotEmpty;

  /// Whether streams are addressed per episode rather than per season.
  bool get isEpisodic => episodePlayers.isNotEmpty;

  /// Episode numbers that actually have a stream, ascending.
  List<int> get playableEpisodes {
    final numbers =
        episodePlayers.entries
            .where((entry) => entry.value.values.any((list) => list.isNotEmpty))
            .map((entry) => entry.key)
            .toList()
          ..sort();
    return numbers;
  }

  Map<String, List<PlayerSource>> _mapFor(int? episode) {
    if (!isEpisodic) return playerData;
    if (episode != null) return episodePlayers[episode] ?? const {};
    final playable = playableEpisodes;
    return playable.isEmpty ? const {} : episodePlayers[playable.first]!;
  }

  /// Provider keys that really carry a stream, in the order [players] lists.
  List<String> availablePlayers({int? episode}) {
    final map = _mapFor(episode);
    final ordered = <String>[
      for (final key in players)
        if (map[key]?.isNotEmpty ?? false) key,
    ];
    // A provider that ships a stream without being listed still plays; keep it
    // rather than hiding it.
    final extra = map.entries
        .where(
          (entry) => entry.value.isNotEmpty && !ordered.contains(entry.key),
        )
        .map((entry) => entry.key);
    return [...ordered, ...extra];
  }

  /// Every stream of [provider], or nothing when it offers none.
  List<PlayerSource> sourcesFor(String provider, {int? episode}) =>
      _mapFor(episode)[provider] ?? const [];

  /// Whether anything can be watched right now — the whole season for a film,
  /// any episode for a series.
  bool get isPlayable {
    if (rightsBlocked) return false;
    if (isEpisodic) return playableEpisodes.isNotEmpty;
    return playerData.values.any((sources) => sources.isNotEmpty);
  }

  static Map<String, List<PlayerSource>> _providers(JsonMap? raw) {
    if (raw == null) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is List)
          entry.key: [
            for (final item in entry.value as List<dynamic>)
              if (item is Map)
                PlayerSource.fromJson(item.cast<String, dynamic>()),
          ],
    };
  }

  static Map<int, Map<String, List<PlayerSource>>> _episodes(JsonMap? raw) {
    if (raw == null) return const {};
    return {
      for (final entry in raw.entries)
        if (int.tryParse(entry.key) case final number?)
          if (entry.value is Map)
            number: _providers((entry.value as Map).cast<String, dynamic>()),
    };
  }

  @override
  String toString() => isEpisodic
      ? 'Season($number, ${playableEpisodes.length} playable episodes)'
      : 'Season($number, ${availablePlayers().length} players)';
}

/// Everything the title page shows.
final class ContentDetails {
  const ContentDetails({
    required this.id,
    required this.name,
    required this.originalName,
    required this.slug,
    required this.typeRaw,
    required this.format,
    required this.isSeries,
    required this.posterUrl,
    required this.genres,
    required this.seasons,
    required this.cast,
    required this.directors,
    required this.ratingsCount,
    required this.commentsCount,
    this.type,
    this.imdbMark,
    this.averageRating,
    this.sliderUrl,
    this.yearStart,
    this.yearEnd,
    this.ageRestrictions,
    this.shortDescription,
    this.time,
    this.country,
    this.trailerYoutubeId,
    this.franchise,
  });

  factory ContentDetails.fromJson(JsonMap json) {
    const owner = 'ContentDetails';
    final franchise = json.mapOrNull('franchise');
    return ContentDetails(
      id: json.requireInt('id', owner: owner),
      name: json.requireString('name', owner: owner),
      originalName: json.requireString('original_name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      typeRaw: json.requireString('type_raw', owner: owner),
      type: ContentType.tryParse(json.stringOrNull('type')),
      format: json.requireString('format', owner: owner),
      isSeries: json.boolOr('is_series'),
      posterUrl: json.requireString('poster_url', owner: owner),
      genres: json.listOf('genres', Genre.fromJson),
      seasons: json.listOf('seasons', Season.fromJson),
      cast: json.listOf('cast', Credit.fromJson),
      directors: json.listOf('directors', Credit.fromJson),
      ratingsCount: json.intOr('ratings_count'),
      commentsCount: json.intOr('comments_count'),
      imdbMark: json.doubleOrNull('imdb_mark'),
      averageRating: json.intOrNull('average_rating'),
      sliderUrl: json.stringOrNull('slider_url'),
      yearStart: json.intOrNull('year_start'),
      yearEnd: json.intOrNull('year_end'),
      ageRestrictions: json.intOrNull('age_restrictions'),
      shortDescription: json.stringOrNull('short_description'),
      time: json.stringOrNull('time'),
      country: json.stringOrNull('country'),
      trailerYoutubeId: json.stringOrNull('trailer_youtube_id'),
      franchise: franchise == null ? null : Franchise.fromJson(franchise),
    );
  }

  /// Numeric, and what the comments endpoint takes — it will not take a slug.
  final int id;

  final String name;
  final String originalName;
  final String slug;

  final ContentType? type;
  final String typeRaw;

  /// `film` or `serial`.
  final String format;
  final bool isSeries;

  final String posterUrl;

  /// The wide backdrop behind the title.
  final String? sliderUrl;

  final List<Genre> genres;

  /// Ascending. A film has exactly one, numbered `1`, carrying the players.
  final List<Season> seasons;

  final List<Credit> cast;
  final List<Credit> directors;

  /// The site's own rating out of 10, `null` until the first vote.
  final int? averageRating;
  final int ratingsCount;
  final int commentsCount;

  final double? imdbMark;
  final int? yearStart;
  final int? yearEnd;
  final int? ageRestrictions;
  final String? shortDescription;

  /// A localised runtime string like `1 год 50 хв`.
  final String? time;
  final String? country;
  final String? trailerYoutubeId;

  final Franchise? franchise;

  /// The season carrying a film's streams, i.e. its only one.
  Season? get firstSeason => seasons.isEmpty ? null : seasons.first;

  /// Lowest-numbered season with a stream — where a first watch starts.
  ///
  /// A long-running series often lists every season it ever had while carrying
  /// data for only some, so this is not simply `seasons.first`.
  Season? get firstPlayableSeason {
    Season? found;
    for (final season in seasons) {
      if (season.isPlayable &&
          (found == null || season.number < found.number)) {
        found = season;
      }
    }
    return found;
  }

  /// Highest-numbered season with a stream.
  Season? get latestPlayableSeason {
    Season? found;
    for (final season in seasons) {
      if (season.isPlayable &&
          (found == null || season.number > found.number)) {
        found = season;
      }
    }
    return found;
  }

  /// Whether anything at all can be watched right now.
  bool get isPlayable => seasons.any((season) => season.isPlayable);

  @override
  String toString() => 'ContentDetails($slug, id $id)';
}
