import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/error_message.dart';
import '../../core/load_status.dart';
import '../../data/playlist_store.dart';

/// One playlist with its titles resolved to cards.
class PlaylistView extends Equatable {
  const PlaylistView({required this.playlist, required this.items});

  final Playlist playlist;

  /// The cards, in the playlist's own order. Shorter than `playlist.slugs`
  /// when the catalogue no longer carries something that was added.
  final List<ContentCard> items;

  @override
  List<Object?> get props => [playlist.id, playlist.title, items];
}

class PlaylistsState extends Equatable {
  const PlaylistsState({
    this.status = LoadStatus.initial,
    this.mine = const [],
    this.featured = const [],
    this.publicAvailable = false,
    this.error,
  });

  final LoadStatus status;

  /// The owner's own playlists.
  final List<PlaylistView> mine;

  /// Collections the catalogue publishes. Empty until that endpoint exists.
  final List<PlaylistView> featured;

  /// Whether the catalogue offers public collections at all — the screen says
  /// something different for "none yet" than for "not a feature here".
  final bool publicAvailable;

  final String? error;

  bool get isEmpty => mine.isEmpty && featured.isEmpty;

  PlaylistsState copyWith({
    LoadStatus? status,
    List<PlaylistView>? mine,
    List<PlaylistView>? featured,
    bool? publicAvailable,
    String? error,
  }) => PlaylistsState(
    status: status ?? this.status,
    mine: mine ?? this.mine,
    featured: featured ?? this.featured,
    publicAvailable: publicAvailable ?? this.publicAvailable,
    error: error,
  );

  @override
  List<Object?> get props => [status, mine, featured, publicAvailable, error];
}

class PlaylistsCubit extends Cubit<PlaylistsState> {
  PlaylistsCubit(this._api, this._store, this._public)
    : super(const PlaylistsState());

  final SuperMoviesApi _api;
  final PlaylistStore _store;
  final PublicPlaylists _public;

  Future<void> load() async {
    emit(
      state.copyWith(
        status: LoadStatus.loading,
        publicAvailable: _public.isAvailable,
      ),
    );

    final playlists = _store.all;
    final featured = _public.isAvailable
        ? await _public.featured()
        : const <Playlist>[];

    // One batch for every slug on the screen, rather than one call per
    // playlist: the endpoint takes a list, and a box pays for round trips.
    final slugs = <String>{
      for (final playlist in playlists) ...playlist.slugs,
      for (final playlist in featured) ...playlist.slugs,
    }.toList();

    if (slugs.isEmpty) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: LoadStatus.success,
          mine: [
            for (final playlist in playlists)
              PlaylistView(playlist: playlist, items: const []),
          ],
          featured: const [],
        ),
      );
      return;
    }

    try {
      final cards = await _api.cards(slugs);
      if (isClosed) return;

      final bySlug = {for (final card in cards) card.slug: card};
      List<PlaylistView> view(List<Playlist> source) => [
        for (final playlist in source)
          PlaylistView(
            playlist: playlist,
            // Keeps the playlist's order, and drops anything the catalogue no
            // longer has rather than leaving a hole.
            items: [for (final slug in playlist.slugs) ?bySlug[slug]],
          ),
      ];

      emit(
        state.copyWith(
          status: LoadStatus.success,
          mine: view(playlists),
          featured: view(featured),
        ),
      );
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(status: LoadStatus.failure, error: describeError(error)),
      );
    }
  }

  Future<void> create(String title) async {
    await _store.create(title);
    await load();
  }

  Future<void> rename(String id, String title) async {
    await _store.rename(id, title);
    await load();
  }

  Future<void> remove(String id) async {
    await _store.remove(id);
    await load();
  }
}
