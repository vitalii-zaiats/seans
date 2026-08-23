import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import 'package:go_router/go_router.dart';

import '../../core/navigate.dart';
import '../../core/home_hero.dart';
import '../../core/home_rails.dart';
import '../../core/nav_tab.dart';
import '../../platform/box_for_platform.dart';
import '../../data/camera_store.dart';
import '../../data/library_store.dart';
import '../../data/settings_store.dart';
import '../../data/startup.dart';
import '../../theme/nocturne.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/rail.dart';
import '../../widgets/status_views.dart';
import '../player/player_route.dart';
import 'home_cubit.dart';
import 'home_state.dart';
import 'widgets/clock_hero.dart';
import 'widgets/hero_panel.dart';
import 'widgets/pinned_apps_rail.dart';
import 'widgets/tv_rail.dart';
import 'widgets/top_bar.dart';

/// The launcher's first screen: hero on top, rails under it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.scrollController, super.key});

  /// Owned by the shell so HOME can return it to the top.
  final ScrollController scrollController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Where the highlight sits while the home screen itself is showing.
  NavTab _destination = NavTab.home;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        // Without a Material ancestor every Text here falls back to Flutter's
        // debug style — yellow, double-underlined. The other screens get one
        // from their own Scaffold; this one is built straight into the shell.
        return Scaffold(
          body: Column(
            children: [
              TopBar(
                destinations: _tabs(context),
                selected: _destination,
                link: state.link,
                onSelect: _openDestination,
                onEnter: _toTop,
              ),
              Expanded(
                child: _Body(state: state, controller: widget.scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Puts the rails back at the top when focus walks up into the bar.
  ///
  /// The bar is outside the scrollable, so without this, going up from a rail
  /// highlights a tab while the hero stays half off the screen — and pressing
  /// down again returns to the rail rather than to the hero, so there is no way
  /// back to it at all.
  void _toTop() {
    final controller = widget.scrollController;
    if (!controller.hasClients || controller.offset <= 0) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// The sections this box shows, in their declared order.
  ///
  /// A section switched off in settings is not drawn at all — the point of
  /// switching it off is that somebody does not want it, and a greyed-out tab
  /// would still be in the way of the ones they do.
  List<NavTab> _tabs(BuildContext context) {
    final settings = context.read<SettingsStore>().value;
    // Cameras are the one section that appears on its own: a box with none is
    // most boxes, and an empty tab in everybody's way is worse than a tab that
    // turns up when it has something in it.
    final hasCameras = !context.read<CameraStore>().isEmpty;
    // What the server said this build may carry. A shop that reviews the build
    // decides some of this, not the owner — so it is checked before the
    // owner's own switches rather than after: a section that is not allowed
    // must not be reachable by having been switched on before it was withdrawn.
    final startup = context.watch<Startup>();

    return [
      for (final tab in NavTab.values)
        if (!tab.needsBox || platformBox.present)
          if (startup.allows(tab.id))
            if (!tab.optional || settings.showsTab(tab.id))
              if (tab != NavTab.cameras || hasCameras) tab,
    ];
  }

  Future<void> _openDestination(NavTab tab) async {
    if (tab == NavTab.home) return;

    // On the web a section is a *place*, not a screen laid on top of this one.
    //
    // `push` records an imperative route and deliberately leaves the address
    // alone, so every section read `/` in the bar: nothing could be linked to,
    // a reload always landed back here, and the browser's own Back returned to
    // this screen while the bar still had the section underlined — the tab
    // highlight and the stack had come apart.
    //
    // `go` makes it an address. This screen is disposed on the way out and
    // rebuilt on the way back, so the highlight below has nothing to restore
    // and cannot fall out of step.
    if (kIsWeb) {
      context.go(tab.path);
      return;
    }

    // On a box there is no address bar to be right about, and BACK is a key
    // somebody presses — so a section stays a screen pushed on top, and the
    // highlight moves at once and comes back when it closes.
    setState(() => _destination = tab);
    await openRoute<void>(context, tab.path);
    if (mounted) setState(() => _destination = NavTab.home);
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.controller});

  final HomeState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (state.status.isFailure) {
      return ErrorView(
        message: state.error ?? 'Не вдалося завантажити',
        onRetry: context.read<HomeCubit>().refresh,
      );
    }
    if (!state.status.isSuccess) return const LoadingView();

    final hero = state.heroCard;
    final library = context.read<LibraryStore>();
    final settings = context.read<SettingsStore>().value;
    bool shows(HomeRailId rail) => settings.showsRail(rail.id);

    return ListView(
      controller: controller,
      padding: EdgeInsets.only(bottom: context.px(40)),
      children: [
        if (settings.heroMode == HomeHero.clock) const ClockHero(),
        if (hero != null && settings.heroMode == HomeHero.slider)
          HeroPanel(
            card: hero,
            progress: state.heroProgress,
            saved: library.isSaved(hero.slug),
            index: state.heroIndex,
            count: state.hero.length,
            onHold: (held) => context.read<HomeCubit>().holdHero(held: held),
            onPlay: () => _play(context, hero),
            onDetails: () => _details(context, hero.slug),
            onToggleSaved: () async {
              await library.toggleSaved(hero.slug);
              if (context.mounted) {
                await context.read<HomeCubit>().refreshLocalRails();
              }
            },
          ),
        // First rail whenever there is one: what somebody stopped halfway
        // through is the likeliest reason they turned the box on.
        if (state.resume.isNotEmpty && shows(HomeRailId.resume)) ...[
          SizedBox(height: context.px(28)),
          Rail(
            title: 'Продовжити дивитись',
            itemCount: state.resume.length,
            itemBuilder: (context, index) {
              final entry = state.resume[index];
              return PosterTile(
                card: entry.card,
                progress: entry.progress.fraction,
                subtitle: entry.label,
                onSelect: () => _play(
                  context,
                  entry.card,
                  resumeAt: entry.progress.position,
                  season: entry.progress.season,
                  episode: entry.progress.episode,
                ),
              );
            },
          ),
        ],
        // Right after what is half-watched, and before the content rails: this
        // is what a launcher is for, and reaching YouTube should not mean
        // walking to the Застосунки tab.
        if (shows(HomeRailId.apps)) ...[
          SizedBox(height: context.px(28)),
          const PinnedAppsRail(),
        ],

        // Live channels next, because reaching for the news is the other thing
        // a box gets turned on for — and the ТБ tab is four presses away.
        if (shows(HomeRailId.tv)) ...[
          SizedBox(height: context.px(28)),
          const TvRail(),
        ],

        for (final rail in state.rails)
          if (rail.items.isNotEmpty) ...[
            SizedBox(height: context.px(28)),
            Rail(
              title: rail.title,
              itemCount: rail.items.length,
              itemBuilder: (context, index) => PosterTile(
                card: rail.items[index],
                onSelect: () => _details(context, rail.items[index].slug),
              ),
            ),
          ],
        SizedBox(height: context.px(20)),
        const KeyHints(text: '←→↑↓ навігація  ·  OK відкрити  ·  ⌫ назад'),
      ],
    );
  }

  Future<void> _details(BuildContext context, String slug) async {
    await openRoute<void>(context, '/title/$slug');
    if (context.mounted) await context.read<HomeCubit>().refreshLocalRails();
  }

  Future<void> _play(
    BuildContext context,
    ContentCard card, {
    Duration? resumeAt,
    int? season,
    int? episode,
  }) async {
    // A card carries no seasons, so the detail payload is fetched on the way to
    // the player. Opening details is the honest fallback when it cannot be.
    await openPlayerForSlug(
      context,
      slug: card.slug,
      resumeAt: resumeAt,
      season: season,
      episode: episode,
    );
    if (context.mounted) await context.read<HomeCubit>().refreshLocalRails();
  }
}
