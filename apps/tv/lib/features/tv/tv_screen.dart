import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigate.dart';
import '../../core/router.dart';
import '../../data/iptv_store.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/status_views.dart';
import 'live_channel.dart';
import 'widgets/channel_tile.dart';
import 'tv_cubit.dart';

/// Live channels: groups across the top, the channels of one below.
class TvScreen extends StatelessWidget {
  const TvScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.read<IptvStore>();

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<TvCubit, TvState>(
          builder: (context, state) {
            if (state.status.isFailure) {
              return ErrorView(
                message: state.error ?? 'Не вдалося завантажити канали',
                onRetry: context.read<TvCubit>().load,
              );
            }
            if (!state.status.isSuccess) return const LoadingView();

            return ValueListenableBuilder<Set<String>>(
              valueListenable: store.favouritesListenable,
              builder: (context, starred, _) {
                final channels = state.visible(starred);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.px(80),
                        context.px(44),
                        context.px(80),
                        context.px(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'ТБ',
                            style: TextStyle(
                              fontSize: context.sp(38),
                              fontWeight: FontWeight.w500,
                              color: Nocturne.text,
                            ),
                          ),
                          SizedBox(width: context.px(16)),
                          Text(
                            '${channels.length} каналів',
                            style: TextStyle(
                              fontSize: context.sp(17),
                              color: Nocturne.neutral600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                      child: TvChipRow(
                        itemCount: state.groups.length + 1,
                        builder: (context, index) {
                          if (index == 0) {
                            return TvChip(
                              label: 'Усі',
                              selected: state.group == null,
                              autofocus: state.group == null,
                              onSelect: () =>
                                  context.read<TvCubit>().showGroup(null),
                            );
                          }
                          final group = state.groups[index - 1];
                          return TvChip(
                            label: group,
                            selected: group == state.group,
                            onSelect: () =>
                                context.read<TvCubit>().showGroup(group),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: context.px(18)),

                    Expanded(
                      child: channels.isEmpty
                          ? EmptyView(
                              message: state.group == TvState.favourites
                                  ? 'Тут будуть канали, які ви позначите '
                                        'зірочкою'
                                  : 'У цій групі порожньо',
                            )
                          : _Channels(channels: channels, starred: starred),
                    ),

                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.px(80),
                        0,
                        context.px(80),
                        context.px(20),
                      ),
                      child: Text(
                        'OK дивитись  ·  ⏯ в обране  ·  ⌫ назад',
                        style: TextStyle(
                          fontSize: context.sp(14),
                          color: Nocturne.neutral700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Channels extends StatelessWidget {
  const _Channels({required this.channels, required this.starred});

  final List<LiveChannel> channels;
  final Set<String> starred;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TvCubit>();
    final store = context.read<IptvStore>();

    return GridView.builder(
      clipBehavior: Clip.none,
      padding: EdgeInsets.fromLTRB(
        context.px(80),
        context.px(10),
        context.px(80),
        context.px(30),
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.px(300),
        childAspectRatio: 2.4,
        crossAxisSpacing: context.px(16),
        mainAxisSpacing: context.px(16),
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) => ChannelTile(
        channel: channels[index],
        starred: starred.contains(channels[index].id),
        autofocus: index == 0,
        onSelect: () => openRoute(
          context,
          '/tv/${Uri.encodeComponent(channels[index].name)}',
          extra: LiveArgs(channel: channels[index], cubit: cubit),
        ),
        onStar: () => store.toggleFavourite(channels[index].id),
      ),
    );
  }
}
