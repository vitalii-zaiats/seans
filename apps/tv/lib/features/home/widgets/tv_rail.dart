import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iptv/iptv.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../../core/navigate.dart';
import '../../../core/router.dart';
import '../../../data/iptv_store.dart';
import '../../../data/sweet_tv_store.dart';
import '../../../theme/nocturne.dart';
import '../../tv/live_channel.dart';
import '../../tv/tv_cubit.dart';
import '../../tv/widgets/channel_tile.dart';

/// Live channels on the home screen.
///
/// Starred first, then the rest of the list — somebody who marked five channels
/// wants those five, and everything after them is there so a fresh box still
/// shows something. The full list stays on the ТБ tab; this is the shortcut.
class TvRail extends StatelessWidget {
  const TvRail({super.key});

  /// How many fit before the row stops being a shortcut and starts being the
  /// list it was meant to save you from.
  static const max = 24;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TvCubit(
        context.read<IptvLoader>(),
        context.read<IptvStore>(),
        context.read<SuperMoviesApi>(),
        context.read<SweetTvStore>(),
      )..load(),
      child: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final store = context.read<IptvStore>();

    return BlocBuilder<TvCubit, TvState>(
      builder: (context, state) {
        // A row that failed to load says nothing at all: live TV is a bonus on
        // this screen, and an error where a row should be is worse than a gap.
        if (!state.status.isSuccess || state.channels.isEmpty) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<Set<String>>(
          valueListenable: store.favouritesListenable,
          builder: (context, starred, _) {
            final shown = _order(state.channels, starred);
            final cubit = context.read<TvCubit>();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: context.px(80)),
                  child: Text(
                    'ТБ',
                    style: TextStyle(
                      fontSize: context.sp(22),
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                ),
                SizedBox(height: context.px(14)),
                SizedBox(
                  // Padding, logo and two lines of text come to just under 80;
                  // the slack is for a font that measures a shade taller than
                  // Roboto does.
                  height: context.px(88),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => SizedBox(width: context.px(16)),
                    itemBuilder: (context, index) => ChannelTile(
                      channel: shown[index],
                      starred: starred.contains(shown[index].id),
                      width: context.px(300),
                      onSelect: () => openRoute(
                        context,
                        '/tv/${Uri.encodeComponent(shown[index].name)}',
                        extra: LiveArgs(channel: shown[index], cubit: cubit),
                      ),
                      onStar: () => store.toggleFavourite(shown[index].id),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Starred channels first, in playlist order, then everything else.
List<LiveChannel> _order(List<LiveChannel> channels, Set<String> starred) {
  if (starred.isEmpty) return channels.take(TvRail.max).toList();
  return [
    ...channels.where((channel) => starred.contains(channel.id)),
    ...channels.where((channel) => !starred.contains(channel.id)),
  ].take(TvRail.max).toList();
}
