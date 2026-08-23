import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/home_hero.dart';
import '../../core/home_rails.dart';
import '../../data/library_store.dart';
import '../../data/settings_store.dart';
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

/// The launcher's first screen: hero on top, rails under it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.scrollController, super.key});

  /// Owned by the shell so HOME can return it to the top.
  final ScrollController scrollController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        // Without a Material ancestor every Text here falls back to Flutter's
        // debug style — yellow, double-underlined. The other screens get one
        // from their own Scaffold; this one is built straight into the shell.
        //
        // The section row used to be drawn here, above this body. It belongs to
        // the shell now: it was disappearing the moment you left the home
        // screen, because it was part of the screen you were leaving.
        return Scaffold(
          body: _Body(state: state, controller: widget.scrollController),
        );
      },
    );
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
