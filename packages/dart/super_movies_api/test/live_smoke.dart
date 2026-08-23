import 'package:super_movies_api/super_movies_api.dart';

Future<void> main() async {
  final api = SuperMoviesApi(baseUrl: Uri.parse('http://127.0.0.1:8077'));

  final trending = await api.trending(type: ContentType.movie);
  print('trending: ${trending.length} cards');
  final first = trending.first;
  print(
    '  ${first.name} | ${first.yearLabel} | imdb ${first.imdbMark} | ${first.time}',
  );

  final filters = await api.catalogFilters();
  print('filters: ${filters.byType.keys.map((t) => t.slug).join(', ')}');
  final movie = filters[ContentType.movie]!;
  print(
    '  movie: ${movie.allGenres.length} genres, ${movie.totalCount} titles',
  );
  print(
    '  ranges: ${movie.years.where((y) => y.isRange).map((y) => y.slug).join(', ')}',
  );

  final page = await api.catalog(type: ContentType.serial, page: 1);
  print(
    'catalog: ${page.length} of ${page.meta.total}, next ${page.meta.nextPage}',
  );

  final hits = await api.search('мерц');
  print('search: ${hits.map((h) => h.card.slug).take(3).join(', ')}');
  print(
    '  spans: ${hits.first.nameSpans().map((s) => s.toString()).join('|')}',
  );

  final details = await api.content(first.slug);
  print(
    'details: ${details.name} | seasons ${details.seasons.length} | cast ${details.cast.length}',
  );
  final season = details.firstPlayableSeason;
  print(
    '  playable: ${details.isPlayable} | season ${season?.number} '
    '| loaded ${season?.isLoaded} | players ${season?.availablePlayers()}',
  );
  final ashdi = season?.sourcesFor('ashdi') ?? const [];
  print('  ashdi sources: ${ashdi.map((s) => s.name).join(', ')}');

  final channels = await api.channels();
  print(
    'tv: ${channels.items.length} channels, ${channels.categories.length} categories',
  );

  api.close();
}
