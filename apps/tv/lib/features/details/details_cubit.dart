import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/error_message.dart';
import '../../core/load_status.dart';

class DetailsState extends Equatable {
  const DetailsState({
    this.status = LoadStatus.initial,
    this.details,
    this.seasons = const [],
    this.seasonIndex = 0,
    this.seasonLoading = false,
    this.saved = false,
    this.error,
  });

  final LoadStatus status;
  final ContentDetails? details;

  /// The working season list.
  ///
  /// Starts as whatever the first request returned — every season number, but
  /// the contents of only one — and entries are replaced as the others are
  /// fetched.
  final List<Season> seasons;

  /// Which season the episode strip is showing.
  final int seasonIndex;

  /// That season is being fetched right now.
  final bool seasonLoading;

  final bool saved;
  final String? error;

  Season? get season {
    if (seasons.isEmpty) return null;
    return seasons[seasonIndex.clamp(0, seasons.length - 1)];
  }

  DetailsState copyWith({
    LoadStatus? status,
    ContentDetails? details,
    List<Season>? seasons,
    int? seasonIndex,
    bool? seasonLoading,
    bool? saved,
    String? error,
  }) => DetailsState(
    status: status ?? this.status,
    details: details ?? this.details,
    seasons: seasons ?? this.seasons,
    seasonIndex: seasonIndex ?? this.seasonIndex,
    seasonLoading: seasonLoading ?? this.seasonLoading,
    saved: saved ?? this.saved,
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    details,
    seasons,
    seasonIndex,
    seasonLoading,
    saved,
    error,
  ];
}

class DetailsCubit extends Cubit<DetailsState> {
  DetailsCubit(this._api, this.slug, {required bool saved})
    : super(DetailsState(saved: saved));

  final SuperMoviesApi _api;
  final String slug;

  /// Guards against a slow season landing after the user has moved on.
  int _seasonRequest = 0;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    try {
      final details = await _api.content(slug);
      if (isClosed) return;

      // Open on the season the API actually filled in. For a long-running show
      // that is rarely season one, and every other season is a bare number
      // until it is asked for.
      final index = details.seasons.indexWhere((season) => season.isLoaded);

      emit(
        state.copyWith(
          status: LoadStatus.success,
          details: details,
          seasons: details.seasons,
          seasonIndex: index < 0 ? 0 : index,
        ),
      );
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(status: LoadStatus.failure, error: describeError(error)),
      );
    }
  }

  /// Shows a season, fetching it the first time it is looked at.
  Future<void> showSeason(int index) async {
    if (index < 0 || index >= state.seasons.length) return;

    final season = state.seasons[index];
    emit(state.copyWith(seasonIndex: index, seasonLoading: !season.isLoaded));
    if (season.isLoaded) return;

    final token = ++_seasonRequest;
    try {
      final filled = await _api.content(slug, season: season.number);
      if (isClosed || token != _seasonRequest) return;

      final fetched = filled.seasons
          .where((s) => s.number == season.number && s.isLoaded)
          .firstOrNull;

      emit(
        state.copyWith(
          seasonLoading: false,
          seasons: fetched == null
              ? state.seasons
              : [
                  for (final existing in state.seasons)
                    if (existing.number == fetched.number)
                      fetched
                    else
                      existing,
                ],
        ),
      );
    } on ApiException catch (error) {
      if (isClosed || token != _seasonRequest) return;
      emit(state.copyWith(seasonLoading: false, error: describeError(error)));
    }
  }

  void setSaved(bool saved) => emit(state.copyWith(saved: saved));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
