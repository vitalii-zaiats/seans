import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/navigate.dart';
import '../../core/error_message.dart';
import '../../core/load_status.dart';
import '../../data/playlist_store.dart';
import '../../theme/nocturne.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/status_views.dart';

/// Everything in one playlist, as a grid.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  LoadStatus _status = LoadStatus.initial;
  List<ContentCard> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Playlist? get _playlist =>
      context.read<PlaylistStore>().byId(widget.playlistId);

  Future<void> _load() async {
    final playlist = _playlist;
    if (playlist == null || playlist.isEmpty) {
      setState(() {
        _status = LoadStatus.success;
        _items = const [];
      });
      return;
    }

    setState(() => _status = LoadStatus.loading);
    try {
      final cards = await context.read<SuperMoviesApi>().cards(playlist.slugs);
      if (!mounted) return;
      final bySlug = {for (final card in cards) card.slug: card};
      setState(() {
        _status = LoadStatus.success;
        // The playlist's own order, minus anything the catalogue dropped.
        _items = [for (final slug in playlist.slugs) ?bySlug[slug]];
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = LoadStatus.failure;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    playlist?.title ?? 'Плейлист',
                    style: TextStyle(
                      fontSize: context.sp(34),
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                  SizedBox(height: context.px(6)),
                  Text(
                    '${_items.length} тайтлів  ·  прибрати можна зі сторінки '
                    'тайтла',
                    style: TextStyle(
                      fontSize: context.sp(16),
                      color: Nocturne.neutral600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_status.isFailure) {
      return ErrorView(
        message: _error ?? 'Не вдалося завантажити',
        onRetry: _load,
      );
    }
    if (_status.isLoading) return const LoadingView();
    if (_items.isEmpty) {
      return const EmptyView(
        message: 'Тут поки порожньо. Додавайте зі сторінки тайтла.',
      );
    }

    return GridView.builder(
      clipBehavior: Clip.none,
      padding: EdgeInsets.fromLTRB(
        context.px(80),
        context.px(18),
        context.px(80),
        context.px(40),
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.px(220),
        childAspectRatio: 0.52,
        crossAxisSpacing: context.px(20),
        mainAxisSpacing: context.px(24),
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) => PosterTile(
        card: _items[index],
        autofocus: index == 0,
        onSelect: () async {
          await openRoute(context, '/title/${_items[index].slug}');
          // Membership is changed on the title's own page, so the grid may be
          // stale by the time it comes back.
          if (mounted) await _load();
        },
      ),
    );
  }
}
