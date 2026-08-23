import 'package:flutter/material.dart';

import '../../../theme/nocturne.dart';
import '../../../widgets/focusable.dart';
import '../../../widgets/poster_image.dart';
import '../live_channel.dart';

/// One live channel, wherever it is shown.
///
/// The same tile in the ТБ grid and in the home row on purpose: a channel that
/// looked one way on the home screen and another in the full list would read as
/// two different things.
class ChannelTile extends StatefulWidget {
  const ChannelTile({
    required this.channel,
    required this.starred,
    required this.onSelect,
    required this.onStar,
    this.autofocus = false,
    this.width,
    super.key,
  });

  final LiveChannel channel;
  final bool starred;
  final VoidCallback onSelect;
  final VoidCallback onStar;
  final bool autofocus;

  /// Fixed width for a horizontal row; the grid sizes its own cells.
  final double? width;

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    // What is on now, when the source says. A playlist never does, and the
    // second line simply does not appear rather than sitting there empty.
    final now = channel.nowPlaying;

    return Focusable(
      autofocus: widget.autofocus,
      scaleOnFocus: 1.03,
      onSelect: widget.onSelect,
      onSecondary: widget.onStar,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) revealOnFocus(context, alignment: 0.3);
      },
      child: Container(
        width: widget.width,
        padding: EdgeInsets.all(context.px(14)),
        decoration: BoxDecoration(
          color: _focused ? context.accentTint : context.surface,
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: context.px(56),
              height: context.px(40),
              child: PosterImage(
                url: channel.logoUrl,
                fit: BoxFit.contain,
                placeholderIcon: Icons.live_tv_outlined,
              ),
            ),
            SizedBox(width: context.px(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(19),
                      color: Nocturne.text,
                    ),
                  ),
                  if (now != null)
                    Text(
                      now,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.sp(14),
                        color: _focused
                            ? context.accentSoft
                            : Nocturne.neutral600,
                      ),
                    )
                  else if (channel.number != null)
                    Text(
                      '№ ${channel.number}',
                      style: TextStyle(
                        fontSize: context.sp(14),
                        color: Nocturne.neutral600,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.starred)
              Icon(
                Icons.star_rounded,
                size: context.px(20),
                color: context.accent,
              ),
          ],
        ),
      ),
    );
  }
}
