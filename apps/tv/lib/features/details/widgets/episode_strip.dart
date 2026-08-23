import 'package:flutter/material.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../../core/labels.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/chip_row.dart';

/// Season chips over a row of episode chips.
///
/// Both rows are the same compact shape: on a television the strip is
/// something you walk along with a thumb, and twenty full-height panels are
/// twenty presses to cross.
class EpisodeStrip extends StatelessWidget {
  const EpisodeStrip({
    required this.seasons,
    required this.seasonIndex,
    required this.loading,
    required this.onSeason,
    required this.onPlay,
    super.key,
  });

  /// The working season list: every number the series has, with the contents
  /// of the ones that have been fetched.
  final List<Season> seasons;

  final int seasonIndex;

  /// The selected season is being fetched.
  final bool loading;

  final ValueChanged<int> onSeason;
  final ValueChanged<int> onPlay;

  @override
  Widget build(BuildContext context) {
    final season = seasons[seasonIndex.clamp(0, seasons.length - 1)];
    // The API lists episodes it has not published yet; those have no stream
    // behind them, so they are shown but not selectable.
    final playable = season.playableEpisodes.toSet();
    final episodes = season.episodes.isNotEmpty
        ? season.episodes
        : [
            for (final number in season.playableEpisodes)
              Episode(number: number, ready: true),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seasons.length > 1)
          TvChipRow(
            itemCount: seasons.length,
            builder: (context, index) => TvChip(
              label: 'Сезон ${seasons[index].number}',
              selected: index == seasonIndex,
              onSelect: () => onSeason(index),
            ),
          ),
        SizedBox(height: context.px(12)),
        if (loading)
          SizedBox(
            height: context.px(56),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: context.px(26),
                height: context.px(26),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.accent,
                ),
              ),
            ),
          )
        else if (episodes.isEmpty)
          SizedBox(
            height: context.px(56),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                // Only ever reached for a season that came back filled in and
                // genuinely empty — an unfetched one shows the spinner.
                'Епізодів ще немає',
                style: TextStyle(
                  fontSize: context.sp(18),
                  color: Nocturne.neutral600,
                ),
              ),
            ),
          )
        else
          TvChipRow(
            itemCount: episodes.length,
            builder: (context, index) {
              final episode = episodes[index];
              final enabled = playable.contains(episode.number);
              return TvChip(
                label: episodeLabel(episode.number, episode.name),
                enabled: enabled,
                hint: enabled ? null : 'ще не вийшла',
                onSelect: () => onPlay(episode.number),
              );
            },
          ),
        const Spacer(),
      ],
    );
  }
}
