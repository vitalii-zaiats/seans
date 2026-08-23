import 'package:flutter/material.dart';

import '../../../core/labels.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/chip_row.dart';

import 'package:hls/hls.dart';

import '../player_cubit.dart';

/// What is playing, changed without leaving the picture.
///
/// A band across the foot rather than a dialog: the film keeps running above
/// it, which is how somebody tells one voice-over from another — and rows of
/// chips are what the D-pad already knows how to walk.
class PlaybackPicker extends StatelessWidget {
  const PlaybackPicker({
    required this.state,
    required this.onSeason,
    required this.onEpisode,
    required this.onDub,
    required this.onQuality,
    super.key,
  });

  final PlayerState state;
  final ValueChanged<int> onSeason;
  final ValueChanged<int> onEpisode;
  final ValueChanged<int> onDub;

  /// `null` hands the choice back to the player, which changes track as the
  /// connection does.
  final ValueChanged<HlsVariant?> onQuality;

  @override
  Widget build(BuildContext context) {
    final episodes = state.episodes;
    final playable = state.season?.playableEpisodes.toSet() ?? const <int>{};

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          context.px(80),
          context.px(28),
          context.px(80),
          context.px(32),
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.ground.withValues(alpha: 0),
              context.ground.withValues(alpha: 0.92),
              context.ground,
            ],
            stops: const [0, 0.28, 1],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.canSwitchSeason) ...[
              const TvChipRowLabel(text: 'СЕЗОН'),
              SizedBox(height: context.px(10)),
              TvChipRow(
                itemCount: state.seasons.length,
                builder: (context, index) {
                  final season = state.seasons[index];
                  return TvChip(
                    label: 'Сезон ${season.number}',
                    selected: season.number == state.seasonNumber,
                    onSelect: () => onSeason(season.number),
                  );
                },
              ),
              SizedBox(height: context.px(18)),
            ],
            if (episodes.isNotEmpty || state.seasonLoading) ...[
              const TvChipRowLabel(text: 'СЕРІЯ'),
              SizedBox(height: context.px(10)),
              if (state.seasonLoading)
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
              else
                TvChipRow(
                  itemCount: episodes.length,
                  builder: (context, index) {
                    final episode = episodes[index];
                    final enabled = playable.contains(episode.number);
                    return TvChip(
                      label: episodeLabel(episode.number, episode.name),
                      selected: episode.number == state.episode,
                      enabled: enabled,
                      preferred: episode.number == state.episode,
                      hint: enabled ? null : 'ще не вийшла',
                      onSelect: () => onEpisode(episode.number),
                    );
                  },
                ),
              SizedBox(height: context.px(18)),
            ],
            if (state.dubs.isNotEmpty) ...[
              const TvChipRowLabel(text: 'ОЗВУЧКА'),
              SizedBox(height: context.px(10)),
              TvChipRow(
                itemCount: state.dubs.length,
                builder: (context, index) => TvChip(
                  label: state.dubs[index].label,
                  selected: index == state.selected,
                  // A film has nothing above this row, so focus lands here.
                  preferred:
                      !state.canSwitchSeason &&
                      state.episodes.isEmpty &&
                      index == state.selected,
                  onSelect: () => onDub(index),
                ),
              ),
              SizedBox(height: context.px(16)),
            ],
            if (state.qualities.variants.length > 1) ...[
              const TvChipRowLabel(text: 'ЯКІСТЬ'),
              SizedBox(height: context.px(10)),
              TvChipRow(
                itemCount: state.qualities.variants.length + 1,
                builder: (context, index) {
                  if (index == 0) {
                    return TvChip(
                      label: 'Авто',
                      hint: 'за швидкістю мережі',
                      selected: state.quality == null,
                      onSelect: () => onQuality(null),
                    );
                  }
                  final variant = state.qualities.variants[index - 1];
                  return TvChip(
                    label: variant.label,
                    hint: variant.bandwidth > 0
                        ? '${(variant.bandwidth / 1000000).toStringAsFixed(1)} '
                              'Мбіт'
                        : null,
                    selected: state.quality?.url == variant.url,
                    onSelect: () => onQuality(variant),
                  );
                },
              ),
              SizedBox(height: context.px(16)),
            ],
            Text(
              'OK обрати  ·  ⌫ закрити',
              style: TextStyle(
                fontSize: context.sp(14),
                color: Nocturne.neutral600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
