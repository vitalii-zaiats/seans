import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/labels.dart';
import '../../data/library_store.dart';
import '../../theme/nocturne.dart';
import '../../widgets/poster_image.dart';
import '../../widgets/status_views.dart';
import '../home/widgets/hero_panel.dart';
import '../player/player_route.dart';
import 'details_cubit.dart';
import 'widgets/episode_strip.dart';

/// The title's page, drawn over a blurred still of its own backdrop.
class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetailsCubit, DetailsState>(
      builder: (context, state) {
        if (state.status.isFailure) {
          return Scaffold(
            body: ErrorView(
              message: state.error ?? 'Не вдалося завантажити',
              onRetry: context.read<DetailsCubit>().load,
            ),
          );
        }
        final details = state.details;
        if (details == null) {
          return const Scaffold(body: LoadingView());
        }
        return Scaffold(
          body: _Body(state: state, details: details),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.details});

  final DetailsState state;
  final ContentDetails details;

  @override
  Widget build(BuildContext context) {
    final season = state.season;
    final library = context.read<LibraryStore>();
    final progress = library.progressFor(details.slug);

    // Where "Дивитись" goes: back to where somebody stopped, else the start.
    // Deliberately independent of the season strip — browsing season twelve of
    // a show whose season twelve has not been fetched must not break the
    // button.
    Season? resumeSeason;
    final wantedSeason = progress?.season;
    if (wantedSeason != null) {
      for (final candidate in state.seasons) {
        if (candidate.number == wantedSeason) {
          resumeSeason = candidate;
          break;
        }
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PosterImage(url: details.sliderUrl ?? details.posterUrl),
        // The overlay sits on a darkened still rather than on a flat ground, so
        // it reads as the same screen rather than a new one.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  context.ground,
                  context.ground.withValues(alpha: 0.94),
                  context.ground.withValues(alpha: 0.70),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.px(80),
              context.px(56),
              context.px(80),
              context.px(40),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Tags(details: details),
                SizedBox(height: context.px(16)),
                SizedBox(
                  width: context.px(1000),
                  child: Text(
                    details.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(52),
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                ),
                SizedBox(height: context.px(10)),
                Text(
                  metaLine([
                    details.yearStart?.toString(),
                    details.time,
                    details.imdbMark == null
                        ? null
                        : '★ ${ratingLabel(details.imdbMark)}',
                    details.directors.isEmpty
                        ? null
                        : 'Реж. ${details.directors.first.name}',
                  ]),
                  style: TextStyle(
                    fontSize: context.sp(18),
                    color: Nocturne.neutral500,
                  ),
                ),
                if (details.shortDescription != null) ...[
                  SizedBox(height: context.px(18)),
                  SizedBox(
                    width: context.px(900),
                    child: Text(
                      details.shortDescription!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.sp(19),
                        height: 1.55,
                        color: Nocturne.neutral400,
                      ),
                    ),
                  ),
                ],
                if (details.cast.isNotEmpty) ...[
                  SizedBox(height: context.px(14)),
                  Text(
                    'У ролях — ${details.cast.take(4).map((c) => c.name).join(', ')}',
                    style: TextStyle(
                      fontSize: context.sp(16),
                      color: Nocturne.neutral600,
                    ),
                  ),
                ],
                SizedBox(height: context.px(26)),
                Row(
                  children: [
                    HeroButton(
                      label: progress != null && progress.isStarted
                          ? 'Продовжити · ${(progress.fraction * 100).round()}%'
                          : 'Дивитись',
                      icon: Icons.play_arrow_rounded,
                      primary: true,
                      autofocus: true,
                      onSelect: () => openPlayer(
                        context,
                        details: details,
                        season: resumeSeason,
                        episode: progress?.episode,
                        resumeAt: progress?.position,
                      ),
                    ),
                    SizedBox(width: context.px(14)),
                    HeroButton(
                      label: 'Плейлисти',
                      icon: Icons.playlist_add_rounded,
                      onSelect: () => openRoute(
                        context,
                        Uri(
                          path: '/title/${details.slug}/add',
                          queryParameters: {'name': details.name},
                        ).toString(),
                      ),
                    ),
                    SizedBox(width: context.px(14)),
                    HeroButton(
                      label: state.saved ? 'У списку' : 'Мій список',
                      icon: state.saved
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      onSelect: () async {
                        final saved = await library.toggleSaved(details.slug);
                        if (context.mounted) {
                          context.read<DetailsCubit>().setSaved(saved);
                        }
                      },
                    ),
                  ],
                ),
                if (details.isSeries && state.seasons.isNotEmpty) ...[
                  SizedBox(height: context.px(28)),
                  Expanded(
                    child: EpisodeStrip(
                      seasons: state.seasons,
                      seasonIndex: state.seasonIndex,
                      loading: state.seasonLoading,
                      onSeason: context.read<DetailsCubit>().showSeason,
                      onPlay: (episode) => openPlayer(
                        context,
                        details: details,
                        season: season,
                        episode: episode,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.details});

  final ContentDetails details;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      for (final genre in details.genres.take(2)) genre.name.toUpperCase(),
      if (details.country != null) details.country!.toUpperCase(),
      if (details.ageRestrictions != null) '${details.ageRestrictions}+',
    ];

    return Wrap(
      spacing: context.px(10),
      children: [
        for (final tag in tags)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.px(12),
              vertical: context.px(5),
            ),
            decoration: BoxDecoration(
              color: context.accentTint,
              borderRadius: BorderRadius.circular(context.px(4)),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: context.sp(13),
                letterSpacing: 1.1,
                color: context.accentSoft,
              ),
            ),
          ),
      ],
    );
  }
}
