import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/error_message.dart';
import '../../core/load_status.dart';

class CatalogState extends Equatable {
  const CatalogState({
    this.status = LoadStatus.initial,
    this.filters,
    this.type = ContentType.movie,
    this.genreSlug,
    this.yearSlug,
    this.items = const [],
    this.meta,
    this.loadingMore = false,
    this.error,
  });

  /// Status of the current first-page load. Stays `success` while another page
  /// is appended — that is what [loadingMore] is for.
  final LoadStatus status;

  /// Genre and year vocabulary, fetched once and reused for every section.
  final CatalogFilters? filters;

  final ContentType type;
  final String? genreSlug;
  final String? yearSlug;

  final List<ContentCard> items;
  final PageMeta? meta;
  final bool loadingMore;
  final String? error;

  /// Genres and years for the section currently selected.
  ContentTypeFilters? get sectionFilters => filters?[type];

  bool get canLoadMore => meta?.hasNextPage ?? false;

  bool get hasActiveFilters => genreSlug != null || yearSlug != null;

  CatalogState copyWith({
    LoadStatus? status,
    CatalogFilters? filters,
    ContentType? type,
    String? genreSlug,
    bool clearGenre = false,
    String? yearSlug,
    bool clearYear = false,
    List<ContentCard>? items,
    PageMeta? meta,
    bool? loadingMore,
    String? error,
  }) => CatalogState(
    status: status ?? this.status,
    filters: filters ?? this.filters,
    type: type ?? this.type,
    genreSlug: clearGenre ? null : (genreSlug ?? this.genreSlug),
    yearSlug: clearYear ? null : (yearSlug ?? this.yearSlug),
    items: items ?? this.items,
    meta: meta ?? this.meta,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    filters,
    type,
    genreSlug,
    yearSlug,
    items,
    meta,
    loadingMore,
    error,
  ];
}

/// The catalogue: a section, optional genre and year, and a page of results.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._api) : super(const CatalogState());

  final SuperMoviesApi _api;

  /// Incremented on every user-driven reload. A response whose token no longer
  /// matches belongs to a filter the viewer has already moved away from, and
  /// is dropped rather than overwriting fresher results.
  int _requestId = 0;

  /// First load: the filter vocabulary and page one.
  Future<void> start() async {
    if (state.filters == null) unawaited(_loadFilters());
    await _loadFirstPage();
  }

  /// The same, opened straight onto one section, genre or year — what the
  /// browse menu hands over.
  Future<void> startWith({
    required ContentType type,
    String? genreSlug,
    String? yearSlug,
  }) {
    emit(
      state.copyWith(
        type: type,
        genreSlug: genreSlug,
        clearGenre: genreSlug == null,
        yearSlug: yearSlug,
        clearYear: yearSlug == null,
      ),
    );
    return start();
  }

  Future<void> changeType(ContentType type) {
    if (type == state.type) return Future.value();
    // Genre slugs are per-section, so a stale one would filter to nothing.
    emit(state.copyWith(type: type, clearGenre: true, clearYear: true));
    return _loadFirstPage();
  }

  /// Selects a genre, or clears it when the one already applied is picked
  /// again — on a remote that is the only way back off it.
  Future<void> toggleGenre(String slug) {
    final next = slug == state.genreSlug ? null : slug;
    emit(state.copyWith(genreSlug: next, clearGenre: next == null));
    return _loadFirstPage();
  }

  Future<void> toggleYear(String slug) {
    final next = slug == state.yearSlug ? null : slug;
    emit(state.copyWith(yearSlug: next, clearYear: next == null));
    return _loadFirstPage();
  }

  Future<void> clearFilters() {
    if (!state.hasActiveFilters) return Future.value();
    emit(state.copyWith(clearGenre: true, clearYear: true));
    return _loadFirstPage();
  }

  Future<void> retry() async {
    if (state.filters == null) unawaited(_loadFilters());
    await _loadFirstPage();
  }

  /// Appends the next page. Safe to call from a scroll listener: it ignores
  /// re-entry and does nothing on the last page.
  Future<void> loadMore() async {
    if (state.loadingMore || !state.canLoadMore) return;

    final token = _requestId;
    final nextPage = state.meta!.nextPage!;
    emit(state.copyWith(loadingMore: true));

    try {
      final page = await _fetch(nextPage);
      if (isClosed || token != _requestId) return;
      emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          meta: page.meta,
          loadingMore: false,
        ),
      );
    } on ApiException {
      if (isClosed || token != _requestId) return;
      // Keep what is on screen; scrolling again retries.
      emit(state.copyWith(loadingMore: false));
    }
  }

  Future<void> _loadFirstPage() async {
    final token = ++_requestId;
    emit(state.copyWith(status: LoadStatus.loading, loadingMore: false));

    try {
      final page = await _fetch(1);
      if (isClosed || token != _requestId) return;
      emit(
        state.copyWith(
          status: LoadStatus.success,
          items: page.items,
          meta: page.meta,
        ),
      );
    } on ApiException catch (error) {
      if (isClosed || token != _requestId) return;
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          items: const [],
          error: describeError(error),
        ),
      );
    }
  }

  Future<void> _loadFilters() async {
    try {
      final filters = await _api.catalogFilters();
      if (isClosed) return;
      emit(state.copyWith(filters: filters));
    } on ApiException {
      // The grid works without the filter rows; leave them collapsed.
    }
  }

  Future<Paginated<ContentCard>> _fetch(int page) => _api.catalog(
    type: state.type,
    page: page,
    genres: state.genreSlug == null ? null : [state.genreSlug!],
    year: state.yearSlug,
  );
}

/// Marks a future as deliberately not awaited.
void unawaited(Future<void> future) {}
