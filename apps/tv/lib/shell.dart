import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import 'package:go_router/go_router.dart';

import 'core/nav_tab.dart';
import 'core/navigate.dart';
import 'core/router.dart';
import 'data/library_store.dart';
import 'data/settings_store.dart';
import 'features/ambient/ambient_screen.dart';
import 'features/home/home_cubit.dart';
import 'features/home/home_state.dart';
import 'parts/parts.dart';
import 'platform/box.dart';
import 'theme/nocturne.dart';
import 'widgets/back_chip.dart';

/// What the box shows when it has nothing else to show.
///
/// Holds the three things that belong to the launcher rather than to any one
/// screen: what HOME does, what happens after a while of nothing, and the
/// events the box sends unprompted.
class LauncherShell extends StatefulWidget {
  const LauncherShell({required this.child, super.key});

  /// Whatever the router is showing. The shell draws around it and never
  /// decides what it is.
  final Widget child;

  @override
  State<LauncherShell> createState() => _LauncherShellState();
}

class _LauncherShellState extends State<LauncherShell> {
  late final Box _box = context.read<Parts>().box;

  /// How long the box sits untouched before the launcher gets out of the way,
  /// as chosen in settings. Zero minutes means never.
  Duration? get _idleAfter {
    final minutes = context.read<SettingsStore>().value.idleMinutes;
    return minutes > 0 ? Duration(minutes: minutes) : null;
  }

  final _scrollController = ScrollController();

  /// Whether to give the way back a strip at the top.
  ///
  /// Read off the address rather than counted: the router already knows what
  /// is showing and how deep it is, and a second tally of the same thing is a
  /// second thing to get wrong.
  ///
  /// Not over a player: it has its own controls, its own way out and a picture
  /// that goes edge to edge, so a bar above it would letterbox the film to
  /// make room for a button the screen already offers.
  bool get _showsWayBack {
    if (!Settings.pointerByDefault) return false;
    final router = GoRouter.of(context);
    if (isFullBleed(router.state.fullPath)) return false;
    // Anywhere but home has a way out of it, whatever kind of navigation put
    // us here — `closeRoute` works out which. Home itself has none, which is
    // what stops the strip appearing over the screen it would return to.
    return router.canPop() || _awayFromHome(router);
  }

  bool _awayFromHome(GoRouter router) =>
      router.state.matchedLocation != NavTab.home.path;

  StreamSubscription<BoxEvent>? _events;
  Timer? _idle;
  bool _ambient = false;

  /// The router, listened to rather than read.
  ///
  /// Reading it during `build` was enough while every route change also handed
  /// this shell a new child — and a browser's own Back does not always. Closing
  /// an overlaid screen that way left the strip behind, pointing at a stack
  /// that no longer had anything on it. A `ChangeNotifier` is what the delegate
  /// is; subscribing to it is the difference between asking and being told.
  GoRouterDelegate? _delegate;

  HomeCubit? _home;

  @override
  void initState() {
    super.initState();
    _events = _box.events().listen(_onBoxEvent);
    _restartIdleTimer();

    // A preferred display mode is an attribute of a window, not a system
    // setting: it lasts as long as the window does, so the box goes back to
    // its own choice on every restart unless this is asked for again.
    final mode = context.read<SettingsStore>().value.preferredModeId;
    if (mode != 0) unawaited(_box.preferMode(mode));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than in `initState`: reaching for the router means depending
    // on an inherited widget, and doing that before the first build is an
    // assertion failure rather than a subtle bug.
    final delegate = GoRouter.of(context).routerDelegate;
    if (identical(delegate, _delegate)) return;
    _delegate?.removeListener(_onRoute);
    _delegate = delegate..addListener(_onRoute);
  }

  @override
  void dispose() {
    _events?.cancel();
    _delegate?.removeListener(_onRoute);
    _idle?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onRoute() {
    if (mounted) setState(() {});
  }

  void _onBoxEvent(BoxEvent event) {
    switch (event) {
      case HomePressed():
        _goHome();
      case PackagesChanged():
        // The apps screen reads the list when it opens, so there is nothing to
        // refresh here — the event matters only while that screen is up, and it
        // rebuilds on its own next time.
        break;
      case LinkChanged(:final link):
        _home?.setLink(link);
        // A box that has just come back online has an empty home screen behind
        // whatever failed while it was off.
        if (!event.isOffline && (_home?.state.status.isFailure ?? false)) {
          unawaited(_home?.refresh());
        }
    }
  }

  /// The way back, if there is still one when the tap lands.
  ///
  /// `_showsWayBack` asks `canPop()` too, but that answer is from the last
  /// build and this one runs later. Two things close the gap: a second click
  /// before the rebuild has painted — easy with a mouse, and this strip only
  /// exists where there is one — and the browser's own Back, which empties the
  /// stack without going through here at all. Either way the chip is still on
  /// screen, still holding a closure, and `pop()` on an empty stack is a
  /// `GoError` rather than a no-op.
  ///
  /// Nothing, rather than falling back to HOME: reaching this means the pop
  /// already happened a moment ago, so the person is where the button was
  /// going to put them. Jumping them somewhere else would be the surprise.
  void _goBack() => closeRoute(context);

  /// HOME: close whatever is open and put the rails back at the top.
  void _goHome() {
    setState(() => _ambient = false);
    GoRouter.of(context).go(NavTab.home.path);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    _restartIdleTimer();
  }

  void _restartIdleTimer() {
    _idle?.cancel();
    final after = _idleAfter;
    if (after == null) return;
    _idle = Timer(after, () {
      if (mounted) setState(() => _ambient = true);
    });
  }

  /// Any key press is activity — including the one that wakes the box from the
  /// idle screen, which is why this runs before the screens see it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) _restartIdleTimer();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      canRequestFocus: false,
      skipTraversal: true,
      child: BlocProvider(
        create: (context) {
          final cubit = HomeCubit(
            context.read<SuperMoviesApi>(),
            context.read<LibraryStore>(),
            context.read<SettingsStore>(),
          )..load();
          _home = cubit;
          return cubit;
        },
        child: HomeScroll(
          controller: _scrollController,
          child: Stack(
            children: [
              Column(
                children: [
                  // A remote has a BACK key; a browser window and a desktop do
                  // not. The browser's own back button works now that every
                  // screen has an address — this is for a desktop build, and
                  // for anybody who reaches for a button rather than the
                  // browser's chrome.
                  //
                  // A strip of its own rather than something floating over the
                  // screen: every screen here opens with a title in the top
                  // left, which is exactly where a floating one lands.
                  //
                  // Painted, because it sits outside every `Scaffold` — and an
                  // unpainted strip is not transparent, it is the browser's
                  // own white showing through the app.
                  if (_showsWayBack)
                    ColoredBox(
                      color: context.ground,
                      child: SizedBox(
                        height: context.px(64),
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: context.px(28)),
                            child: BackChip(onSelect: _goBack),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: widget.child),
                ],
              ),
              if (_ambient)
                Positioned.fill(
                  child: BlocBuilder<HomeCubit, HomeState>(
                    builder: (context, state) => AmbientScreen(
                      resumeTitle: state.resume.isEmpty
                          ? null
                          : '${state.resume.first.card.name} · '
                                '${(state.resume.first.progress.fraction * 100).round()}%',
                      onWake: _goHome,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The home screen's scroll position, where the shell can reach it.
///
/// HOME puts the rails back at the top, and the shell is what hears HOME — but
/// the screen that scrolls is built by the router, below it. An
/// `InheritedWidget` rather than a `RepositoryProvider`, which refuses a
/// `Listenable` and a `ScrollController` is one.
class HomeScroll extends InheritedWidget {
  const HomeScroll({required this.controller, required super.child, super.key});

  final ScrollController controller;

  static ScrollController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeScroll>()!.controller;

  @override
  bool updateShouldNotify(HomeScroll old) => old.controller != controller;
}
