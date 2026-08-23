import 'package:flutter/material.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../core/labels.dart';
import '../theme/nocturne.dart';
import 'focusable.dart';
import 'poster_image.dart';

/// One card in a rail: the poster, its title, and a line of context.
class PosterTile extends StatefulWidget {
  const PosterTile({
    required this.card,
    required this.onSelect,
    this.autofocus = false,
    this.progress,
    this.subtitle,
    super.key,
  });

  final ContentCard card;
  final VoidCallback onSelect;
  final bool autofocus;

  /// 0–1, drawn as a bar across the poster's foot. Set for the
  /// "Continue watching" rail.
  final double? progress;

  /// Overrides the second line — `42%`, or an episode number.
  final String? subtitle;

  @override
  State<PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<PosterTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: context.px(200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            autofocus: widget.autofocus,
            onSelect: widget.onSelect,
            onFocusChange: (focused) {
              setState(() => _focused = focused);
              if (focused) revealOnFocus(context, alignment: 0.08);
            },
            child: SizedBox(
              height: context.px(280),
              width: context.px(200),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: widget.card.posterUrl),
                  if (widget.progress != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _ProgressBar(fraction: widget.progress!),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: context.px(10)),
          Text(
            widget.card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: context.sp(17),
              color: _focused ? Nocturne.text : Nocturne.neutral400,
            ),
          ),
          Text(
            widget.subtitle ??
                metaLine([
                  widget.card.yearLabel,
                  ratingLabel(widget.card.imdbMark),
                ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: context.sp(14),
              color: Nocturne.neutral600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: context.px(4),
      color: context.ground.withValues(alpha: 0.7),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: ColoredBox(color: context.accent),
      ),
    );
  }
}
