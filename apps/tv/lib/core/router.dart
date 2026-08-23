import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:iptv/iptv.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../data/iptv_store.dart';
import '../data/library_store.dart';
import '../data/onboarding_store.dart';
import '../data/stream_resolver.dart';
import '../data/sweet_tv_store.dart';
import '../features/account/account_screen.dart';
import '../features/catalog/catalog_cubit.dart';
import '../features/catalog/catalog_results_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/details/details_cubit.dart';
import '../features/details/details_screen.dart';
import '../features/home/home_screen.dart';
import '../features/player/player_cubit.dart';
import '../features/player/player_screen.dart';
import '../features/playlists/playlist_picker_screen.dart';
import '../features/playlists/playlist_screen.dart';
import '../features/playlists/playlists_screen.dart';
import '../features/search/search_cubit.dart';
import '../features/search/search_screen.dart';
import '../features/settings/reset_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tv/live_channel.dart';
import '../features/tv/live_player_screen.dart';
import '../features/tv/tv_cubit.dart';
import '../features/tv/tv_screen.dart';
import '../parts/parts.dart';
import '../shell.dart';
import 'nav_tab.dart';

/// Every screen, and the address it answers to.
///
/// Declared in one place for the same reason the tabs and the home rails are:
/// scattered `Navigator.push` calls were how a section could quietly end up
/// unreachable, and here the whole map is one page long.
///
/// In a browser these are the URLs. That is worth more than it looks — back and
/// forward work, a reload lands where it was, and a title can be sent to
/// somebody. On the box nothing changes: the remote presses BACK and the router
/// pops.
///
/// **What is not here.** The sections that are the machine itself — installed
/// apps, the drives, a scan of the local network — come from [Parts], and only
/// the platform that has them names them. A browser build does not merely hide
/// those routes: it never compiled the screens behind them.
///
/// The wizard is handed in rather than looked up. Everything else here reads
/// what it needs off the context, which works because those are provided above
/// the router — the wizard's own dependencies are not, and finding that out at
/// runtime on the one screen a new owner sees first is not a trade worth making.
///
/// **Screens that need more than an address.** A live channel, a file on a stick
/// and a title being played are objects, not identifiers — there is no useful
/// `/storage/play?path=…` when the file is on somebody else's box. Those travel
/// in `extra`, which is gone after a reload, and each redirects to the list it
/// came from rather than opening empty.
GoRouter buildRouter({
  required OnboardingStore onboarding,
  required Parts parts,
  required WidgetBuilder welcome,
}) {
  return GoRouter(
    initialLocation: NavTab.home.path,
    // Rebuilt when the wizard finishes — and when settings put the box back
    // into it, which is why this listens rather than reads once.
    refreshListenable: onboarding.completedListenable,
    redirect: (context, state) {
      final atWelcome = state.matchedLocation == _welcome;
      if (!onboarding.completedListenable.value) {
        return atWelcome ? null : _welcome;
      }
      return atWelcome ? NavTab.home.path : null;
    },
    routes: [
      // Outside the shell on purpose: the wizard is not the launcher yet, and
      // an idle screen that took over halfway through setting one up would be
      // its own kind of rude.
      GoRoute(path: _welcome, builder: (context, state) => welcome(context)),
      // The launcher's own chrome — the idle screen, the HOME key, the way
      // back — wraps every screen rather than being one.
      ShellRoute(
        builder: (context, state, child) => LauncherShell(child: child),
        routes: [
          GoRoute(
            path: NavTab.home.path,
            builder: (context, state) =>
                HomeScreen(scrollController: HomeScroll.of(context)),
            routes: [
              GoRoute(
                path: 'search',
                builder: (context, state) => BlocProvider(
                  create: (context) =>
                      SearchCubit(context.read<SuperMoviesApi>()),
                  child: const SearchScreen(),
                ),
              ),
              GoRoute(
                path: 'catalog',
                builder: (context, state) => const CatalogScreen(),
                routes: [
                  GoRoute(
                    path: ':type',
                    builder: (context, state) {
                      final type = ContentType.tryParse(
                        state.pathParameters['type'],
                      );
                      if (type == null) return const CatalogScreen();
                      return BlocProvider(
                        create: (context) =>
                            CatalogCubit(context.read<SuperMoviesApi>())
                              ..startWith(
                                type: type,
                                genreSlug: state.uri.queryParameters['genre'],
                                yearSlug: state.uri.queryParameters['year'],
                              ),
                        child: const CatalogResultsScreen(),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'tv',
                builder: (context, state) => BlocProvider(
                  create: (context) => TvCubit(
                    context.read<IptvLoader>(),
                    context.read<IptvStore>(),
                    context.read<SuperMoviesApi>(),
                    context.read<SweetTvStore>(),
                  )..load(),
                  child: const TvScreen(),
                ),
                routes: [
                  GoRoute(
                    path: ':channel',
                    // A channel is an object with a source behind it, and the
                    // cubit that opens streams is the screen's own — neither
                    // survives a reload, so a cold address goes to the list.
                    redirect: (context, state) =>
                        state.extra == null ? NavTab.tv.path : null,
                    builder: (context, state) {
                      final args = state.extra! as LiveArgs;
                      return BlocProvider<TvCubit>.value(
                        value: args.cubit,
                        child: LivePlayerScreen(channel: args.channel),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'playlists',
                builder: (context, state) => const PlaylistsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        PlaylistScreen(playlistId: state.pathParameters['id']!),
                  ),
                ],
              ),
              GoRoute(
                path: 'title/:slug',
                pageBuilder: (context, state) {
                  final slug = state.pathParameters['slug']!;
                  return CustomTransitionPage<void>(
                    key: state.pageKey,
                    // The details screen is drawn over the rails it came from.
                    opaque: false,
                    transitionDuration: const Duration(milliseconds: 260),
                    transitionsBuilder: (_, animation, _, child) =>
                        FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                          child: child,
                        ),
                    child: BlocProvider(
                      create: (context) => DetailsCubit(
                        context.read<SuperMoviesApi>(),
                        slug,
                        saved: context.read<LibraryStore>().isSaved(slug),
                      )..load(),
                      child: const DetailsScreen(),
                    ),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'play',
                    // The player is built around a title whose seasons are
                    // already in hand. Opened cold the address still means
                    // something — just not "start playing" — so it lands on the
                    // title instead.
                    redirect: (context, state) => state.extra == null
                        ? '/title/${state.pathParameters['slug']}'
                        : null,
                    pageBuilder: (context, state) {
                      final args = state.extra! as PlayerArgs;
                      return CustomTransitionPage<void>(
                        key: state.pageKey,
                        transitionDuration: const Duration(milliseconds: 420),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 300,
                        ),
                        transitionsBuilder: (_, animation, _, child) =>
                            FadeTransition(
                              opacity: CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                              child: child,
                            ),
                        child: BlocProvider(
                          create: (context) =>
                              PlayerCubit(
                                context.read<StreamResolver>(),
                                context.read<SuperMoviesApi>(),
                                args.details.slug,
                              )..start(
                                seasons: args.details.seasons,
                                seasonNumber: args.season.number,
                                episode: args.episode,
                              ),
                          child: PlayerScreen(
                            details: args.details,
                            season: args.season,
                            episode: args.episode,
                            resumeAt: args.resumeAt,
                          ),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => PlaylistPickerScreen(
                      slug: state.pathParameters['slug']!,
                      titleName: state.uri.queryParameters['name'] ?? '',
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'account',
                    builder: (context, state) => const AccountScreen(),
                  ),
                  GoRoute(
                    path: 'reset',
                    builder: (context, state) => const ResetScreen(),
                  ),
                ],
              ),
              // The machine's own sections, from whichever platform this is.
              ...parts.routes(),
            ],
          ),
        ],
      ),
    ],
  );
}

const _welcome = '/welcome';

/// What the player needs and an address cannot carry.
class PlayerArgs {
  const PlayerArgs({
    required this.details,
    required this.season,
    this.episode,
    this.resumeAt,
  });

  final ContentDetails details;
  final Season season;
  final int? episode;
  final Duration? resumeAt;
}

/// The same for a live channel, which brings the cubit that opens its stream.
class LiveArgs {
  const LiveArgs({required this.channel, required this.cubit});

  final LiveChannel channel;
  final TvCubit cubit;
}

/// Whether the screen at [pattern] wants the window to itself.
///
/// A player has its own controls, its own way out and a picture that goes edge
/// to edge, so the way-back strip would letterbox the film to make room for a
/// button the screen already offers.
bool isFullBleed(String? pattern) => switch (pattern) {
  '/title/:slug/play' || '/tv/:channel' => true,
  '/cameras/:id' || '/storage/play' => true,
  _ => false,
};
