import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/error_message.dart';
import '../../core/home_rails.dart';
import '../../core/load_status.dart';
import '../../data/library_store.dart';
import '../../data/settings_store.dart';
import 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(
    this._api,
    this._library,
    this._settings, {
    this.heroDwell = const Duration(seconds: 9),
  }) : super(const HomeState());

  final SuperMoviesApi _api;
  final LibraryStore _library;
  final SettingsStore _settings;

  bool _shows(HomeRailId rail) => _settings.value.showsRail(rail.id);

  /// What the last load was built from.
  ///
  /// The whole app rebuilds when settings change, but this cubit outlives that
  /// rebuild — so without watching for it, turning a row back on would do
  /// nothing until the launcher restarted. Everything `load` reads has to be
  /// in here: watching only the hidden rows meant switching the banner back on
  /// left the screen with the empty hero it had fetched in clock mode.
  String? _lastLoadedFrom;

  String get _loadSignature {
    final settings = _settings.value;
    final hidden = settings.hiddenRails.toList()..sort();
    return '${settings.heroMode.id}|${hidden.join(',')}';
  }

  void _onSettingsChanged() {
    if (_lastLoadedFrom == _loadSignature) return;
    _lastLoadedFrom = _loadSignature;
    unawaited(load());
  }

  /// Fills the whole screen in one pass.
  ///
  /// Every rail is an independent request, so they all go out together — on a
  /// box the round trips cost more than the parsing does, and a home screen
  /// that filled in row by row would be visibly slow.
  Future<void> load() async {
    _lastLoadedFrom = _loadSignature;
    _settings.listenable.removeListener(_onSettingsChanged);
    _settings.listenable.addListener(_onSettingsChanged);

    emit(state.copyWith(status: LoadStatus.loading));

    // A row switched off in settings is a request never made, not a widget
    // hidden after the fact — the saving is the round trip, on a box where
    // those cost more than the parsing does.
    final sections = [
      for (final rail in HomeRailId.values)
        if (rail.type != null && _shows(rail)) rail,
    ];

    // A banner nobody will see is a request worth not making either.
    final wantsHero = _settings.value.heroMode.needsSlider;

    try {
      final results = await Future.wait([
        if (wantsHero) _api.slider(),
        if (_shows(HomeRailId.trending)) _api.trending(),
        for (final rail in sections) _api.catalog(type: rail.type),
      ]);

      if (isClosed) return;

      var next = 0;
      final hero = wantsHero
          ? results[next++] as List<ContentCard>
          : const <ContentCard>[];
      final trending = _shows(HomeRailId.trending)
          ? results[next++] as List<ContentCard>
          : const <ContentCard>[];

      emit(
        state.copyWith(
          status: LoadStatus.success,
          hero: hero,
          rails: [
            if (trending.isNotEmpty)
              HomeRail(title: HomeRailId.trending.title, items: trending),
            for (final rail in sections)
              HomeRail(
                title: rail.title,
                items: (results[next++] as Paginated<ContentCard>).items,
              ),
          ],
        ),
      );
      _restartHeroTimer();

      // The two local rails need a second round trip to turn stored slugs back
      // into cards, so they land after the screen is already usable.
      await refreshLocalRails();
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(status: LoadStatus.failure, error: describeError(error)),
      );
    }
  }

  /// Rebuilds "Continue watching" and "Мій список" from local storage.
  ///
  /// Called on every return from the player, which is when the position that
  /// feeds the first of them has just changed.
  Future<void> refreshLocalRails() async {
    final progress = _shows(HomeRailId.resume)
        ? _library.continueWatching()
        : const <WatchProgress>[];
    final saved = _shows(HomeRailId.myList)
        ? _library.myList()
        : const <String>[];

    final slugs = <String>{
      ...progress.map((entry) => entry.slug),
      ...saved,
    }.toList();
    if (slugs.isEmpty) {
      if (isClosed) return;
      emit(state.copyWith(resume: const [], rails: _withMyList(const [])));
      return;
    }

    try {
      final cards = await _api.cards(slugs);
      if (isClosed) return;

      final bySlug = {for (final card in cards) card.slug: card};
      emit(
        state.copyWith(
          resume: [
            for (final entry in progress)
              if (bySlug[entry.slug] case final card?)
                ResumeEntry(card: card, progress: entry),
          ],
          rails: _withMyList([for (final slug in saved) ?bySlug[slug]]),
        ),
      );
    } on ApiException {
      // The API rails are already on screen; a failed batch lookup should not
      // take them down with it.
    }
  }

  List<HomeRail> _withMyList(List<ContentCard> saved) {
    final rails = [
      for (final rail in state.rails)
        if (rail.title != HomeRailId.myList.title) rail,
    ];
    return saved.isEmpty
        ? rails
        : [HomeRail(title: HomeRailId.myList.title, items: saved), ...rails];
  }

  /// How long one hero title stays up. Long enough to read the synopsis
  /// underneath it, which is the only reason the panel carries one.
  ///
  /// Injectable so tests do not have to wait nine seconds a slide.
  final Duration heroDwell;

  Timer? _heroTimer;

  /// Held while the hero's own buttons have focus.
  ///
  /// Rotating under somebody's thumb is the one way this feature can do real
  /// harm: the title changes between reading it and pressing OK, and the wrong
  /// film opens.
  bool _heroHeld = false;

  void _restartHeroTimer() {
    _heroTimer?.cancel();
    if (_heroHeld || state.hero.length < 2) return;
    _heroTimer = Timer(heroDwell, _advanceHero);
  }

  void _advanceHero() {
    if (isClosed || state.hero.isEmpty) return;
    emit(state.copyWith(heroIndex: (state.heroIndex + 1) % state.hero.length));
    _restartHeroTimer();
  }

  /// Stops the carousel while the viewer is on it, and starts it again when
  /// they step off.
  void holdHero({required bool held}) {
    if (held == _heroHeld) return;
    _heroHeld = held;
    _restartHeroTimer();
  }

  void showHero(int index) {
    if (index == state.heroIndex || index < 0 || index >= state.hero.length) {
      return;
    }
    emit(state.copyWith(heroIndex: index));
    // A hand-picked slide gets its full dwell, not whatever was left of the
    // last one.
    _restartHeroTimer();
  }

  void setLink(String link) => emit(state.copyWith(link: link));

  Future<void> refresh() => load();

  @override
  Future<void> close() {
    _heroTimer?.cancel();
    _settings.listenable.removeListener(_onSettingsChanged);
    return super.close();
  }
}
