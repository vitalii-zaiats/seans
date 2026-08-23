import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigate.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/rail.dart';
import '../../widgets/status_views.dart';
import 'playlists_cubit.dart';

/// Lists the owner made, and the ones the catalogue publishes.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  /// The name is typed on a screen of its own, which writes it to the store
  /// and comes back — so there is nothing to hand over, only a list to re-read.
  Future<void> _create(BuildContext context) async {
    await openRoute<void>(context, '/playlists/new');
    if (context.mounted) await context.read<PlaylistsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<PlaylistsCubit, PlaylistsState>(
          builder: (context, state) {
            if (state.status.isFailure) {
              return ErrorView(
                message: state.error ?? 'Не вдалося завантажити плейлисти',
                onRetry: context.read<PlaylistsCubit>().load,
              );
            }
            if (!state.status.isSuccess) return const LoadingView();

            return ListView(
              padding: EdgeInsets.only(bottom: context.px(40)),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.px(80),
                    context.px(44),
                    context.px(80),
                    context.px(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Плейлисти',
                        style: TextStyle(
                          fontSize: context.sp(38),
                          fontWeight: FontWeight.w500,
                          color: Nocturne.text,
                        ),
                      ),
                      SizedBox(height: context.px(16)),
                      TvChipRow(
                        itemCount: 1,
                        builder: (context, index) => TvChip(
                          label: 'Створити плейлист',
                          preferred: true,
                          onSelect: () => _create(context),
                        ),
                      ),
                    ],
                  ),
                ),

                if (state.mine.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                    child: Text(
                      'Поки жодного. Створіть перший — і додавайте в нього '
                      'тайтли зі сторінки фільму чи серіалу.',
                      style: TextStyle(
                        fontSize: context.sp(18),
                        height: 1.5,
                        color: Nocturne.neutral500,
                      ),
                    ),
                  ),

                for (final view in state.mine) ...[
                  SizedBox(height: context.px(24)),
                  _PlaylistRail(view: view, editable: true),
                ],

                SizedBox(height: context.px(36)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                  child: const TvChipRowLabel(text: 'ДОБІРКИ'),
                ),
                SizedBox(height: context.px(10)),

                if (state.featured.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: context.px(80)),
                    child: Text(
                      state.publicAvailable
                          ? 'Готових добірок поки немає.'
                          : 'Готові добірки — на кшталт найкращого за оцінками '
                                'IMDb — зʼявляться, коли їх почне віддавати '
                                'каталог.',
                      style: TextStyle(
                        fontSize: context.sp(18),
                        height: 1.5,
                        color: Nocturne.neutral600,
                      ),
                    ),
                  )
                else
                  for (final view in state.featured) ...[
                    SizedBox(height: context.px(24)),
                    _PlaylistRail(view: view, editable: false),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One playlist as a row of posters, with its own name as the way in.
class _PlaylistRail extends StatelessWidget {
  const _PlaylistRail({required this.view, required this.editable});

  final PlaylistView view;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlaylistsCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.px(80)),
          child: TvChipRow(
            itemCount: editable ? 3 : 1,
            builder: (context, index) => switch (index) {
              0 => TvChip(
                label: view.playlist.title,
                selected: true,
                hint: '${view.playlist.length}',
                onSelect: () =>
                    openRoute(context, '/playlists/${view.playlist.id}'),
              ),
              1 => TvChip(
                label: 'Перейменувати',
                onSelect: () async {
                  await openRoute<void>(
                    context,
                    '/playlists/${view.playlist.id}/rename',
                  );
                  if (context.mounted) await cubit.load();
                },
              ),
              _ => TvChip(
                label: 'Видалити',
                onSelect: () => cubit.remove(view.playlist.id),
              ),
            },
          ),
        ),
        SizedBox(height: context.px(12)),
        if (view.items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.px(80)),
            child: Text(
              'Порожній',
              style: TextStyle(
                fontSize: context.sp(17),
                color: Nocturne.neutral700,
              ),
            ),
          )
        else
          Rail(
            itemCount: view.items.length,
            itemBuilder: (context, index) => PosterTile(
              card: view.items[index],
              onSelect: () =>
                  openRoute(context, '/title/${view.items[index].slug}'),
            ),
          ),
      ],
    );
  }
}
