import 'package:flutter/material.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../../core/labels.dart';
import '../../../core/remote/focus_area.dart';
import '../../../data/library_store.dart';
import '../../../theme/nocturne.dart';
import '../../../widgets/focusable.dart';
import '../../../widgets/poster_image.dart';

/// The split hero: copy on the left, backdrop bleeding in from the right.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    required this.card,
    required this.progress,
    required this.saved,
    required this.index,
    required this.count,
    required this.onPlay,
    required this.onDetails,
    required this.onToggleSaved,
    required this.onHold,
    super.key,
  });

  final ContentCard card;
  final WatchProgress? progress;
  final bool saved;

  /// Which slide is up, and how many there are — the dots at the foot.
  final int index;
  final int count;

  final VoidCallback onPlay;
  final VoidCallback onDetails;
  final VoidCallback onToggleSaved;

  /// Fires when focus enters or leaves the hero's own buttons. The carousel
  /// stops while it is `true`: a title that changes between reading it and
  /// pressing OK opens the wrong film.
  final ValueChanged<bool> onHold;

  @override
  Widget build(BuildContext context) {
    final resumable = progress != null && progress!.isStarted;

    return SizedBox(
      height: context.px(560),
      child: Stack(
        children: [
          // Keyed by slug so the switcher crossfades between titles instead of
          // swapping the image under a still frame.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.sizeOf(context).width * 0.62,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: ShaderMask(
                key: ValueKey('backdrop-${card.slug}'),
                // The picture's own left edge is dissolved rather than covered
                // by a gradient laid over it. A gradient on top only darkens
                // the picture — the edge where it starts is still an edge, and
                // it shows as a hard vertical line. Fading the pixels
                // themselves is what makes it land the way the bottom does,
                // where the ramp happens inside the picture already.
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x00000000), Color(0xFF000000)],
                  stops: [0, 0.42],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: PosterImage(url: card.sliderUrl ?? card.posterUrl),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.ground.withValues(alpha: 0),
                    context.ground.withValues(alpha: 0.85),
                    context.ground,
                  ],
                  stops: const [0.55, 0.88, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.px(80),
              context.px(60),
              0,
              context.px(40),
            ),
            child: SizedBox(
              width: context.px(760),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The copy crossfades with the picture behind it; the button
                  // row underneath does not, so focus never moves mid-fade.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: Column(
                      key: ValueKey('copy-${card.slug}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          metaLine([
                            card.genres.isEmpty ? null : card.genres.first.name,
                            card.yearLabel,
                            card.time,
                            card.imdbMark == null
                                ? null
                                : '★ ${ratingLabel(card.imdbMark)}',
                          ]),
                          style: TextStyle(
                            fontSize: context.sp(17),
                            color: Nocturne.neutral500,
                          ),
                        ),
                        SizedBox(height: context.px(12)),
                        Text(
                          card.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: context.sp(56),
                            height: 1.1,
                            fontWeight: FontWeight.w500,
                            color: Nocturne.text,
                          ),
                        ),
                        if (card.shortDescription != null) ...[
                          SizedBox(height: context.px(16)),
                          Text(
                            card.shortDescription!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: context.sp(19),
                              height: 1.5,
                              color: Nocturne.neutral400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: context.px(28)),
                  Focus(
                    // Watches the buttons without ever taking focus itself.
                    // A subscription to somebody resting on the hero, not a
                    // piece of steering.
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: onHold,
                    child: FocusArea(
                      flow: Axis.horizontal,
                      landing: true,
                      child: Row(
                        children: [
                          HeroButton(
                            label: resumable
                                ? 'Продовжити · ${(progress!.fraction * 100).round()}%'
                                : 'Дивитись',
                            icon: Icons.play_arrow_rounded,
                            primary: true,
                            preferred: true,
                            onSelect: onPlay,
                          ),
                          SizedBox(width: context.px(14)),
                          HeroButton(
                            label: 'Деталі',
                            icon: Icons.info_outline_rounded,
                            onSelect: onDetails,
                          ),
                          SizedBox(width: context.px(14)),
                          HeroButton(
                            label: saved ? 'У списку' : 'Мій список',
                            icon: saved
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            onSelect: onToggleSaved,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (count > 1) ...[
                    SizedBox(height: context.px(20)),
                    _Dots(count: count, active: index),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where you are in the carousel. Not focusable — there is nothing to press,
/// and the row of buttons above already owns the remote.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            margin: EdgeInsets.only(right: context.px(6)),
            width: context.px(i == active ? 26 : 8),
            height: context.px(4),
            decoration: BoxDecoration(
              color: i == active ? context.accent : Nocturne.neutral800,
              borderRadius: BorderRadius.circular(context.px(2)),
            ),
          ),
      ],
    );
  }
}

/// An outlined action — the design never fills a button.
class HeroButton extends StatefulWidget {
  const HeroButton({
    required this.label,
    required this.icon,
    required this.onSelect,
    this.primary = false,
    this.preferred = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelect;
  final bool primary;
  final bool preferred;
  final FocusNode? focusNode;

  @override
  State<HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<HeroButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final border = widget.primary || _focused
        ? context.accent
        : Nocturne.neutral700;
    final foreground = _focused ? context.accentText : Nocturne.text;

    return Focusable(
      preferred: widget.preferred,
      focusNode: widget.focusNode,
      onSelect: widget.onSelect,
      scaleOnFocus: 1.04,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(26),
          vertical: context.px(14),
        ),
        decoration: BoxDecoration(
          color: _focused
              ? context.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          border: Border.all(color: border, width: context.px(1)),
          borderRadius: BorderRadius.circular(context.px(Nocturne.radius)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: context.px(22), color: foreground),
            SizedBox(width: context.px(10)),
            Text(
              widget.label,
              style: TextStyle(fontSize: context.sp(18), color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
