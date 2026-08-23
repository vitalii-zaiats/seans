import '../exceptions.dart';
import '../json.dart';

/// The five content sections the catalogue exposes.
///
/// The [slug] is what goes into the `type` query parameter and what the server
/// echoes back in card and detail payloads.
enum ContentType {
  movie('movie'),
  serial('serial'),
  cartoonMovie('cartoon-movie'),
  cartoonSeries('cartoon-series'),
  anime('anime');

  const ContentType(this.slug);

  /// Wire value, e.g. `cartoon-movie`.
  final String slug;

  /// The matching type, or `null` for an unrecognised value.
  ///
  /// Never throws: a catalogue that grows a sixth section must not break
  /// parsing of the five known ones.
  static ContentType? tryParse(String? slug) {
    for (final type in values) {
      if (type.slug == slug) return type;
    }
    return null;
  }

  @override
  String toString() => slug;
}

/// Gender code attached to people. `0` unspecified, `1` female, `2` male.
enum Gender {
  unspecified(0),
  female(1),
  male(2);

  const Gender(this.code);

  final int code;

  static Gender fromCode(int? code) {
    for (final gender in values) {
      if (gender.code == code) return gender;
    }
    return Gender.unspecified;
  }
}

/// A genre, as it appears in cards, details and the filter directory.
final class Genre {
  const Genre({required this.name, required this.slug});

  factory Genre.fromJson(JsonMap json) => Genre(
    name: json.requireString('name', owner: 'Genre'),
    slug: json.requireString('slug', owner: 'Genre'),
  );

  /// Localised label, e.g. `Бойовик`.
  final String name;

  /// Query value, e.g. `bojovik`.
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is Genre && other.name == name && other.slug == slug;

  @override
  int get hashCode => Object.hash(name, slug);

  @override
  String toString() => 'Genre($slug)';
}

/// A selectable value for the catalogue's `year` filter.
///
/// The catalogue mixes single years with ranges (`2006-2010`) and one
/// open-ended bucket (`2000-1900`), so the value stays a string. [isRange] is
/// sent rather than derived, so a client never has to parse it.
final class YearOption {
  const YearOption({
    required this.name,
    required this.slug,
    required this.isRange,
  });

  factory YearOption.fromJson(JsonMap json) {
    const owner = 'YearOption';
    return YearOption(
      name: json.requireString('name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      isRange: json.boolOr('is_range'),
    );
  }

  final String name;
  final String slug;
  final bool isRange;

  @override
  bool operator ==(Object other) =>
      other is YearOption && other.name == name && other.slug == slug;

  @override
  int get hashCode => Object.hash(name, slug);

  @override
  String toString() => 'YearOption($slug)';
}

/// The `meta` block on every paginated answer.
final class PageMeta {
  const PageMeta({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.hasNextPage,
  });

  factory PageMeta.fromJson(JsonMap json) {
    const owner = 'PageMeta';
    return PageMeta(
      page: json.requireInt('page', owner: owner),
      perPage: json.requireInt('per_page', owner: owner),
      total: json.requireInt('total', owner: owner),
      totalPages: json.requireInt('total_pages', owner: owner),
      hasNextPage: json.boolOr('has_next_page'),
    );
  }

  /// 1-based index of the page that came back.
  final int page;
  final int perPage;

  /// Across all pages, not on this one.
  final int total;
  final int totalPages;
  final bool hasNextPage;

  /// The page to ask for next, or `null` on the last one.
  int? get nextPage => hasNextPage ? page + 1 : null;

  @override
  String toString() => 'PageMeta(page $page/$totalPages, total $total)';
}

/// A `{ "items": [...], "meta": {...} }` answer.
final class Paginated<T> {
  const Paginated({required this.items, required this.meta});

  factory Paginated.fromJson(JsonMap json, T Function(JsonMap json) parseItem) {
    final meta = json.mapOrNull('meta');
    if (meta == null) {
      throw ApiSerializationException(
        'expected a `meta` object on a paginated answer',
      );
    }
    return Paginated<T>(
      items: json.listOf('items', parseItem),
      meta: PageMeta.fromJson(meta),
    );
  }

  final List<T> items;
  final PageMeta meta;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get length => items.length;

  bool get hasNextPage => meta.hasNextPage;

  @override
  String toString() => 'Paginated<$T>(${items.length} items, $meta)';
}

/// Publication progress of a season, as a card summarises it.
final class ReadySeason {
  const ReadySeason({
    required this.number,
    required this.readyEpisodesCount,
    this.lastReadyEpisode,
    this.lastUrlSuffix,
  });

  factory ReadySeason.fromJson(JsonMap json) {
    const owner = 'ReadySeason';
    return ReadySeason(
      number: json.requireInt('number', owner: owner),
      readyEpisodesCount: json.intOr('ready_episodes_count'),
      lastReadyEpisode: json.intOrNull('last_ready_episode'),
      lastUrlSuffix: json.stringOrNull('last_url_suffix'),
    );
  }

  /// 1-based season number.
  final int number;

  /// How many episodes of it are watchable.
  final int readyEpisodesCount;

  /// The newest watchable episode; `null` for a film, whose single season
  /// carries no episode list.
  final int? lastReadyEpisode;

  /// The path fragment the website appends to deep-link the newest episode.
  final String? lastUrlSuffix;

  @override
  String toString() => 'ReadySeason($number, $readyEpisodesCount eps)';
}

/// A title in list form.
///
/// One class covers the catalogue, the trending rail, the hero slider and a
/// search hit, because they are the same object with different amounts of
/// detail. Fields only some of them populate are nullable, and each says where
/// it comes from.
final class ContentCard {
  const ContentCard({
    required this.name,
    required this.originalName,
    required this.slug,
    required this.typeRaw,
    required this.format,
    required this.posterUrl,
    required this.genres,
    required this.seasonsCount,
    required this.isSeries,
    this.type,
    this.imdbMark,
    this.yearStart,
    this.yearEnd,
    this.yearLabel,
    this.lastUpdatePage,
    this.firstReadySeason,
    this.lastReadySeason,
    this.sliderPosterUrl,
    this.sliderUrl,
    this.shortDescription,
    this.time,
    this.country,
    this.ageRestrictions,
    this.trailerYoutubeId,
    this.averageRating,
    this.ratingsCount,
  });

  factory ContentCard.fromJson(JsonMap json) {
    const owner = 'ContentCard';
    final firstReady = json.mapOrNull('first_ready_season');
    final lastReady = json.mapOrNull('last_ready_season');
    return ContentCard(
      name: json.requireString('name', owner: owner),
      originalName: json.requireString('original_name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      typeRaw: json.requireString('type_raw', owner: owner),
      type: ContentType.tryParse(json.stringOrNull('type')),
      format: json.requireString('format', owner: owner),
      posterUrl: json.requireString('poster_url', owner: owner),
      genres: json.listOf('genres', Genre.fromJson),
      seasonsCount: json.intOr('seasons_count'),
      isSeries: json.boolOr('is_series'),
      imdbMark: json.doubleOrNull('imdb_mark'),
      yearStart: json.intOrNull('year_start'),
      yearEnd: json.intOrNull('year_end'),
      yearLabel: json.stringOrNull('year_label'),
      lastUpdatePage: json.dateTimeOrNull('last_update_page'),
      firstReadySeason: firstReady == null
          ? null
          : ReadySeason.fromJson(firstReady),
      lastReadySeason: lastReady == null
          ? null
          : ReadySeason.fromJson(lastReady),
      sliderPosterUrl: json.stringOrNull('slider_poster_url'),
      sliderUrl: json.stringOrNull('slider_url'),
      shortDescription: json.stringOrNull('short_description'),
      time: json.stringOrNull('time'),
      country: json.stringOrNull('country'),
      ageRestrictions: json.intOrNull('age_restrictions'),
      trailerYoutubeId: json.stringOrNull('trailer_youtube_id'),
      averageRating: json.intOrNull('average_rating'),
      ratingsCount: json.intOrNull('ratings_count'),
    );
  }

  /// Localised title.
  final String name;

  /// Title in the original language.
  final String originalName;

  /// The identifier the detail page and the website URL both use.
  final String slug;

  /// Parsed section, or `null` when upstream sent one this package does not
  /// know — [typeRaw] always holds the original string, so the row is still
  /// worth showing.
  final ContentType? type;
  final String typeRaw;

  /// `film` or `serial`, and independent of [type]: an anime can be either.
  final String format;

  final String posterUrl;
  final List<Genre> genres;

  /// Number of seasons; `1` for a film.
  final int seasonsCount;

  /// Whether it has episodes.
  final bool isSeries;

  /// IMDb score, `7` or `6.4` upstream, always a double here.
  final double? imdbMark;

  final int? yearStart;

  /// End year of a finished multi-year series; `null` for a film and for one
  /// still running.
  final int? yearEnd;

  /// `2019`, `2019 – 2023`, or `2019 – …`, already assembled — so every screen
  /// does not assemble it slightly differently.
  final String? yearLabel;

  /// When the page was last touched upstream. Absent on the slider.
  final DateTime? lastUpdatePage;

  final ReadySeason? firstReadySeason;
  final ReadySeason? lastReadySeason;

  /// Wide artwork. Trending and the slider only.
  final String? sliderPosterUrl;
  final String? sliderUrl;

  /// Synopsis. Trending and the slider.
  final String? shortDescription;

  /// A localised runtime string like `1 год 50 хв`, not a duration.
  final String? time;

  final String? country;

  /// Minimum age. The slider only.
  final int? ageRestrictions;

  /// YouTube id of the trailer. The slider only.
  final String? trailerYoutubeId;

  /// The site's own rating and its vote count. Batch card lookups only.
  final int? averageRating;
  final int? ratingsCount;

  @override
  bool operator ==(Object other) => other is ContentCard && other.slug == slug;

  @override
  int get hashCode => slug.hashCode;

  @override
  String toString() => 'ContentCard($slug, $typeRaw)';
}

/// One hit from a search.
final class SearchResult {
  const SearchResult({required this.card, this.highlightedName});

  factory SearchResult.fromJson(JsonMap json) {
    final card = json.mapOrNull('card');
    if (card == null) {
      throw ApiSerializationException('expected a `card` object on a hit');
    }
    return SearchResult(
      card: ContentCard.fromJson(card),
      highlightedName: json.stringOrNull('highlighted_name'),
    );
  }

  final ContentCard card;

  /// The title with the matched span in `<mark>`. Absent more often than not,
  /// so never rely on it — [nameSpans] falls back for you.
  final String? highlightedName;

  /// The name split into runs, each flagged with whether the server matched it.
  ///
  /// Falls back to the plain name as one unmatched run, so a caller renders the
  /// same way whether or not a highlight came back.
  List<NameSpan> nameSpans() {
    final marked = highlightedName;
    if (marked == null) return [NameSpan(card.name, matched: false)];

    const openTag = '<mark>';
    const closeTag = '</mark>';

    final spans = <NameSpan>[];
    var rest = marked;
    while (true) {
      final open = rest.indexOf(openTag);
      if (open < 0) break;
      final close = rest.indexOf(closeTag, open);
      if (close < 0) break;

      if (open > 0) {
        spans.add(NameSpan(rest.substring(0, open), matched: false));
      }
      spans.add(
        NameSpan(rest.substring(open + openTag.length, close), matched: true),
      );
      rest = rest.substring(close + closeTag.length);
    }
    if (rest.isNotEmpty) spans.add(NameSpan(rest, matched: false));

    return spans.isEmpty ? [NameSpan(card.name, matched: false)] : spans;
  }

  @override
  String toString() => 'SearchResult(${card.slug})';
}

/// A run of a hit's title, and whether the server matched it.
final class NameSpan {
  const NameSpan(this.text, {required this.matched});

  final String text;

  /// Draw this run in the accent when true — it is what the query hit.
  final bool matched;

  @override
  bool operator ==(Object other) =>
      other is NameSpan && other.text == text && other.matched == matched;

  @override
  int get hashCode => Object.hash(text, matched);

  @override
  String toString() => matched ? '[$text]' : text;
}

/// An entry of the people directory.
final class Person {
  const Person({
    required this.name,
    required this.originalName,
    required this.slug,
    required this.gender,
    required this.careerRoles,
    this.posterUrl,
  });

  factory Person.fromJson(JsonMap json) {
    const owner = 'Person';
    return Person(
      name: json.requireString('name', owner: owner),
      originalName: json.requireString('original_name', owner: owner),
      slug: json.requireString('slug', owner: owner),
      gender: Gender.fromCode(json.intOrNull('gender')),
      careerRoles: (json['career_roles'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      posterUrl: json.stringOrNull('poster_url'),
    );
  }

  final String name;
  final String originalName;
  final String slug;
  final Gender gender;

  /// `['actor']`, `['actor', 'director']`.
  final List<String> careerRoles;

  /// Headshot; `null` when there is none.
  final String? posterUrl;

  bool get isActor => careerRoles.contains('actor');
  bool get isDirector => careerRoles.contains('director');

  @override
  String toString() => 'Person($slug)';
}

/// The genre and year options available for one section.
final class ContentTypeFilters {
  const ContentTypeFilters({
    required this.popularGenres,
    required this.otherGenres,
    required this.years,
    required this.totalCount,
  });

  factory ContentTypeFilters.fromJson(JsonMap json) => ContentTypeFilters(
    popularGenres: json.listOf('popular_genres', Genre.fromJson),
    otherGenres: json.listOf('other_genres', Genre.fromJson),
    years: json.listOf('years', YearOption.fromJson),
    totalCount: json.intOr('total_count'),
  );

  /// The ones the site surfaces up front.
  final List<Genre> popularGenres;

  /// The long tail, behind a "more" toggle.
  final List<Genre> otherGenres;

  final List<YearOption> years;

  /// How many titles the section holds.
  final int totalCount;

  /// Popular first, then the rest.
  List<Genre> get allGenres => [...popularGenres, ...otherGenres];

  Genre? genreBySlug(String slug) {
    for (final genre in allGenres) {
      if (genre.slug == slug) return genre;
    }
    return null;
  }

  @override
  String toString() =>
      'ContentTypeFilters(${allGenres.length} genres, $totalCount titles)';
}

/// One [ContentTypeFilters] per section.
final class CatalogFilters {
  const CatalogFilters({required this.byType, this.unknownTypes = const []});

  factory CatalogFilters.fromJson(JsonMap json) {
    final sections = json.mapOrNull('by_type') ?? const <String, dynamic>{};
    return CatalogFilters(
      byType: {
        for (final entry in sections.entries)
          if (ContentType.tryParse(entry.key) case final type?)
            if (entry.value is Map)
              type: ContentTypeFilters.fromJson(
                (entry.value as Map).cast<String, dynamic>(),
              ),
      },
      unknownTypes: (json['unknown_types'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  final Map<ContentType, ContentTypeFilters> byType;

  /// Sections upstream grew that this package does not model yet. Empty in
  /// normal operation.
  final List<String> unknownTypes;

  ContentTypeFilters? operator [](ContentType type) => byType[type];

  int get totalCount =>
      byType.values.fold(0, (sum, filters) => sum + filters.totalCount);

  @override
  String toString() => 'CatalogFilters(${byType.keys.join(', ')})';
}
