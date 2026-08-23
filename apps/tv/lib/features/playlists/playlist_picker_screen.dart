import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigate.dart';
import '../../core/remote/focus_area.dart';
import '../../data/playlist_store.dart';
import '../../theme/nocturne.dart';
import '../../widgets/chip_row.dart';
import '../../widgets/focusable.dart';

/// Which playlists one title belongs to.
///
/// A screen rather than a sheet: the list can be long, and on a remote a sheet
/// that scrolls is worse than a page that does.
class PlaylistPickerScreen extends StatefulWidget {
  const PlaylistPickerScreen({
    required this.slug,
    required this.titleName,
    super.key,
  });

  final String slug;

  /// The film's name, shown so it is obvious what is being filed.
  final String titleName;

  @override
  State<PlaylistPickerScreen> createState() => _PlaylistPickerScreenState();
}

class _PlaylistPickerScreenState extends State<PlaylistPickerScreen> {
  PlaylistStore get _store => context.read<PlaylistStore>();

  /// Naming the new list and filing this title into it both happen on the
  /// screen that address opens; all that is left here is to redraw.
  Future<void> _createAndAdd() async {
    await openRoute<void>(context, '/title/${widget.slug}/add/new');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _store.all;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.px(80),
            context.px(44),
            context.px(80),
            context.px(40),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Додати в плейлист',
                style: TextStyle(
                  fontSize: context.sp(34),
                  fontWeight: FontWeight.w500,
                  color: Nocturne.text,
                ),
              ),
              SizedBox(height: context.px(6)),
              Text(
                widget.titleName,
                style: TextStyle(
                  fontSize: context.sp(18),
                  color: Nocturne.neutral500,
                ),
              ),
              SizedBox(height: context.px(24)),

              TvChipRow(
                itemCount: 1,
                builder: (context, index) => TvChip(
                  label: 'Створити новий',
                  preferred: playlists.isEmpty,
                  onSelect: _createAndAdd,
                ),
              ),
              SizedBox(height: context.px(20)),

              Expanded(
                child: playlists.isEmpty
                    ? const _NoPlaylists()
                    : FocusArea(
                        landing: true,
                        child: ListView.builder(
                          clipBehavior: Clip.none,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return _Row(
                              playlist: playlist,
                              holds: playlist.contains(widget.slug),
                              preferred: index == 0,
                              onToggle: () async {
                                await _store.toggle(playlist.id, widget.slug);
                                if (mounted) setState(() {});
                              },
                            );
                          },
                        ),
                      ),
              ),
              SizedBox(height: context.px(10)),
              Text(
                'OK додати або прибрати  ·  ⌫ назад',
                style: TextStyle(
                  fontSize: context.sp(14),
                  color: Nocturne.neutral700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing to file into yet, and nothing focusable — so the area anchors,
/// and the remote still has somewhere to be.
class _NoPlaylists extends StatelessWidget {
  const _NoPlaylists();

  @override
  Widget build(BuildContext context) => FocusArea(
    anchor: true,
    child: Align(
      alignment: Alignment.topLeft,
      child: Text(
        'Плейлистів ще немає — створіть перший.',
        style: TextStyle(fontSize: context.sp(18), color: Nocturne.neutral600),
      ),
    ),
  );
}

class _Row extends StatefulWidget {
  const _Row({
    required this.playlist,
    required this.holds,
    required this.preferred,
    required this.onToggle,
  });

  final Playlist playlist;
  final bool holds;
  final bool preferred;
  final VoidCallback onToggle;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.px(10)),
      child: Focusable(
        preferred: widget.preferred,
        scaleOnFocus: 1,
        onSelect: widget.onToggle,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) revealOnFocus(context, alignment: 0.3);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.px(24),
            vertical: context.px(18),
          ),
          decoration: BoxDecoration(
            color: _focused ? context.accentTint : context.surface,
            border: Border.all(
              color: _focused ? context.accent : Nocturne.neutral800,
              width: context.px(1),
            ),
            borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
          ),
          child: Row(
            children: [
              Icon(
                widget.holds
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: context.px(24),
                color: widget.holds ? context.accent : Nocturne.neutral700,
              ),
              SizedBox(width: context.px(18)),
              Expanded(
                child: Text(
                  widget.playlist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.sp(21),
                    color: Nocturne.text,
                  ),
                ),
              ),
              Text(
                '${widget.playlist.length}',
                style: TextStyle(
                  fontSize: context.sp(16),
                  color: Nocturne.neutral600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
