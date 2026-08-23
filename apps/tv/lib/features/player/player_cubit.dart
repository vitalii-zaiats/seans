import 'package:ashdi_finder/ashdi_finder.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:hls/hls.dart';

import '../../core/error_message.dart';
import '../../data/tls_probe.dart';
import '../../core/load_status.dart';
import '../../data/stream_resolver.dart';

class PlayerState extends Equatable {
  const PlayerState({
    this.status = LoadStatus.initial,
    this.stream,
    this.seasons = const [],
    this.seasonNumber = 1,
    this.episode,
    this.dubs = const [],
    this.selected = -1,
    this.seasonLoading = false,
    this.error,
    this.qualities = const HlsMaster([]),
    this.quality,
  });

  final LoadStatus status;
  final ResolvedStream? stream;

  /// Every season the title has, with the contents of the fetched ones.
  final List<Season> seasons;

  final int seasonNumber;

  /// Which episode is playing; `null` for a film.
  final int? episode;

  /// Every voice-over available for what is playing, in display order.
  final List<DubOption> dubs;

  /// Index into [dubs]; `-1` before anything has resolved.
  final int selected;

  /// A season is being fetched.
  final bool seasonLoading;

  /// What the stream is offered in, once its playlist has been read. Empty for
  /// a stream that offers only one — most do not.
  final HlsMaster qualities;

  /// The chosen variant, or `null` for whatever the player picks itself.
  ///
  /// Null is the better default: ExoPlayer changes track as the connection
  /// changes, and a fixed choice cannot. This exists for the times the guess
  /// is wrong.
  final HlsVariant? quality;

  /// What is actually being played — the chosen variant, or the playlist that
  /// lets the player choose.
  String? get playingUrl => quality?.url ?? stream?.url;

  final String? error;

  Season? get season {
    for (final candidate in seasons) {
      if (candidate.number == seasonNumber) return candidate;
    }
    return null;
  }

  bool get canSwitchDub => dubs.length > 1;

  bool get canSwitchSeason => seasons.length > 1;

  /// The episodes of the current season, as chips would list them.
  List<Episode> get episodes {
    final current = season;
    if (current == null) return const [];
    if (current.episodes.isNotEmpty) return current.episodes;
    return [
      for (final number in current.playableEpisodes)
        Episode(number: number, ready: true),
    ];
  }

  PlayerState copyWith({
    HlsMaster? qualities,
    HlsVariant? quality,
    bool clearQuality = false,
    LoadStatus? status,
    ResolvedStream? stream,
    List<Season>? seasons,
    int? seasonNumber,
    int? episode,
    bool clearEpisode = false,
    List<DubOption>? dubs,
    int? selected,
    bool? seasonLoading,
    String? error,
  }) => PlayerState(
    status: status ?? this.status,
    stream: stream ?? this.stream,
    seasons: seasons ?? this.seasons,
    seasonNumber: seasonNumber ?? this.seasonNumber,
    episode: clearEpisode ? null : (episode ?? this.episode),
    dubs: dubs ?? this.dubs,
    selected: selected ?? this.selected,
    seasonLoading: seasonLoading ?? this.seasonLoading,
    error: error,
    qualities: qualities ?? this.qualities,
    quality: clearQuality ? null : (quality ?? this.quality),
  );

  @override
  List<Object?> get props => [
    status,
    stream?.url,
    quality?.url,
    qualities.variants.length,
    seasons,
    seasonNumber,
    episode,
    dubs,
    selected,
    seasonLoading,
    error,
  ];
}

/// Decides what plays: which season, which episode, which voice-over.
///
/// Playback itself belongs to the controller in the screen — this only ever
/// answers "what URL, and did that work".
class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit(this._resolver, this._api, this.slug)
    : super(const PlayerState());

  final StreamResolver _resolver;
  final SuperMoviesApi _api;

  /// Only ever used to read a playlist that is already being played, so it
  /// needs nothing the rest of the app's clients have.
  final http.Client _http = http.Client();
  final String slug;

  /// Why the last attempt gave up, so the screen can say what went wrong
  /// rather than only that something did.
  String? _lastFailure;

  /// Guards against a slow season landing after the viewer has moved on.
  int _seasonRequest = 0;

  Future<void> start({
    required List<Season> seasons,
    required int seasonNumber,
    int? episode,
  }) {
    emit(
      state.copyWith(
        seasons: seasons,
        seasonNumber: seasonNumber,
        episode: episode,
        clearEpisode: episode == null,
      ),
    );
    return _resolveCurrent();
  }

  /// Switches season, fetching it the first time it is looked at, and lands on
  /// its first playable episode.
  Future<void> selectSeason(int number) async {
    if (number == state.seasonNumber) return;

    var target = state.seasons.where((s) => s.number == number).firstOrNull;
    if (target == null) return;

    emit(state.copyWith(seasonNumber: number, seasonLoading: !target.isLoaded));

    if (!target.isLoaded) {
      final token = ++_seasonRequest;
      try {
        final filled = await _api.content(slug, season: number);
        if (isClosed || token != _seasonRequest) return;

        final fetched = filled.seasons
            .where((s) => s.number == number && s.isLoaded)
            .firstOrNull;
        if (fetched != null) {
          target = fetched;
          emit(
            state.copyWith(
              seasonLoading: false,
              seasons: [
                for (final existing in state.seasons)
                  if (existing.number == number) fetched else existing,
              ],
            ),
          );
        } else {
          emit(state.copyWith(seasonLoading: false));
        }
      } on ApiException catch (error) {
        if (isClosed || token != _seasonRequest) return;
        emit(
          state.copyWith(
            seasonLoading: false,
            status: LoadStatus.failure,
            error: describeError(error),
          ),
        );
        return;
      }
    }

    final first = target.playableEpisodes.firstOrNull;
    emit(state.copyWith(episode: first, clearEpisode: first == null));
    await _resolveCurrent();
  }

  Future<void> selectEpisode(int number) async {
    if (number == state.episode) return;
    emit(state.copyWith(episode: number));
    await _resolveCurrent();
  }

  /// Switches to [index]. The screen keeps the position and seeks back to it.
  Future<void> selectDub(int index) async {
    if (index == state.selected || index < 0 || index >= state.dubs.length) {
      return;
    }

    emit(state.copyWith(status: LoadStatus.loading, selected: index));

    final stream = await _open(state.dubs[index]);
    if (isClosed) return;

    if (stream == null) {
      // Stay on whatever is already playing rather than going black.
      emit(
        state.copyWith(
          status: LoadStatus.success,
          error: 'Ця озвучка недоступна',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: LoadStatus.success,
        stream: stream,
        clearQuality: true,
      ),
    );
    await _readQualities(stream);
  }

  /// Finds a stream for the current season and episode.
  Future<void> _resolveCurrent() async {
    final current = state.season;
    if (current == null) {
      emit(
        state.copyWith(status: LoadStatus.failure, error: 'Цього сезону немає'),
      );
      return;
    }

    if (current.rightsBlocked) {
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          dubs: const [],
          error: 'Недоступно через права',
        ),
      );
      return;
    }

    _lastFailure = null;
    final dubs = _resolver.options(current, episode: state.episode);
    emit(state.copyWith(status: LoadStatus.loading, dubs: dubs, selected: -1));

    if (dubs.isEmpty) {
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          error: 'Для цього тайтла немає джерел',
        ),
      );
      return;
    }

    // Take the first dub that actually gives up a stream — one being
    // unreachable is ordinary, and the next one usually is not.
    for (var index = 0; index < dubs.length; index++) {
      final stream = await _open(dubs[index]);
      if (isClosed) return;
      if (stream != null) {
        emit(
          state.copyWith(
            status: LoadStatus.success,
            stream: stream,
            selected: index,
            clearQuality: true,
          ),
        );
        await _readQualities(stream);
        return;
      }
    }

    // A refused certificate is the one failure worth asking a second question
    // about: it looks the same whether nothing trusts the real certificate or
    // something on the way is answering in ashdi's place, and only the
    // certificate itself tells them apart.
    final report = _tlsFailed ? await probeTls('ashdi.vip') : null;
    if (isClosed) return;

    emit(
      state.copyWith(
        status: LoadStatus.failure,
        error: switch ((_lastFailure, report)) {
          (null, _) => 'Жодне джерело не відповіло',
          (final why, null) => 'Жодне джерело не відповіло — $why',
          (final why, final found?) when !found.matchesHost =>
            'Жодне джерело не відповіло — $why\n\n'
                'Сертифікат виданий не для ashdi.vip. Схоже, відповідає не '
                'сайт, а щось на шляху — провайдер або маршрутизатор.\n'
                '${found.summary}',
          (final why, final found?) =>
            'Жодне джерело не відповіло — $why\n\n${found.summary}',
        },
      ),
    );
  }

  /// Chooses a quality by hand, or hands the choice back to the player.
  ///
  /// The screen reopens the video at the new address and seeks back to where
  /// it was, the same way switching a voice-over works.
  void selectQuality(HlsVariant? variant) {
    if (variant?.url == state.quality?.url) return;
    emit(state.copyWith(quality: variant, clearQuality: variant == null));
  }

  /// Reads what the stream is offered in.
  ///
  /// Best effort and never fatal: a playlist that cannot be read, or one that
  /// is a media playlist rather than a master, simply means there is nothing
  /// to choose between — which is the ordinary case and not worth a word on
  /// screen.
  Future<void> _readQualities(ResolvedStream stream) async {
    final url = stream.url;

    HlsMaster master;
    try {
      final response = await _http
          .get(
            Uri.parse(url),
            headers: {
              // The same headers the player page was read with. ashdi checks
              // both, and answers 400 to a request that carries neither — the
              // one place in this file that has to know that.
              'Referer': stream.embedUrl,
              'User-Agent': StreamResolver.userAgent,
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      master = parseMaster(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        base: Uri.parse(url),
      );
    } on Object {
      return;
    }

    if (isClosed || master.isEmpty) return;
    emit(state.copyWith(qualities: master));
  }

  /// Whether any dub failed on the certificate rather than on the network.
  bool _tlsFailed = false;

  Future<ResolvedStream?> _open(DubOption option) async {
    final current = state.season;
    if (current == null) return null;

    try {
      final stream = await _resolver.resolveOption(
        option,
        // A season that keys its players by episode already points at the
        // right leaf; only a playlist page needs telling which one.
        season: current.isEpisodic ? null : current.number,
        episode: current.isEpisodic ? null : state.episode,
      );
      if (stream == null) _lastFailure = 'сторінка плеєра без потоку';
      return stream;
    } on AshdiException catch (error) {
      _lastFailure = describeAshdiFailure(error);
      _tlsFailed = _tlsFailed || error.cause is HandshakeException;
      return null;
    } on Object catch (error) {
      _lastFailure = describeError(error);
      return null;
    }
  }

  @override
  Future<void> close() {
    _http.close();
    return super.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
