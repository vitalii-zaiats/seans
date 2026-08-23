import 'package:flutter/material.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../../widgets/back_chip.dart';
import '../../../platform/box_for_platform.dart';
import '../../../core/navigate.dart';
import '../../../core/labels.dart';
import '../../../platform/fullscreen.dart';
import '../../../playback/playback.dart';
import '../../../theme/nocturne.dart';

/// The overlay over the picture: what is playing, where it is, and what the
/// remote does. Fades out four seconds after the last press.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    required this.details,
    required this.playback,
    required this.visible,
    required this.resolving,
    this.canSwitchDub = false,
    this.episode,
    this.message,
    this.dub,
    this.onSeek,
    this.onTogglePlay,
    super.key,
  });

  final ContentDetails details;
  final Playback? playback;
  final bool visible;

  /// The stream is still being looked up.
  final bool resolving;

  /// A failure worth showing instead of the controls.
  final String? message;

  /// Which dub is playing, when one is known.
  final String? dub;

  /// Whether the title offers more than one voice-over.
  final bool canSwitchDub;

  final int? episode;

  /// Where to jump to, when somebody points at the scrubber.
  ///
  /// Only reached on a machine with a pointer: a remote seeks with the arrows
  /// and has nothing to aim with.
  final ValueChanged<Duration>? onSeek;

  final VoidCallback? onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      // Faded out, nothing here is aimable — a click would otherwise land on
      // a button nobody can see. With a remote nothing here is aimable ever:
      // the whole overlay is a picture of what the keys do.
      child: IgnorePointer(
        ignoring: !visible || !context.pointer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The copy sits over a gradient so it stays legible whatever frame
            // it lands on.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.80),
                  ],
                  stops: const [0, 0.28, 0.62, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.px(60)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Something to click for a machine with a pointer. A remote
                  // has BACK under a thumb, but a PWA window has no browser
                  // Back and the shell hides its way-back strip over a picture
                  // that goes edge to edge — so there was nothing to aim at.
                  if (!platformBox.present) ...[
                    BackChip(onSelect: () => closeRoute(context)),
                    SizedBox(height: context.px(24)),
                  ],
                  Text(
                    details.name,
                    style: TextStyle(
                      fontSize: context.sp(34),
                      fontWeight: FontWeight.w500,
                      color: Nocturne.text,
                    ),
                  ),
                  SizedBox(height: context.px(6)),
                  Text(
                    metaLine([
                      episode == null ? null : 'Серія $episode',
                      details.genres.isEmpty ? null : details.genres.first.name,
                      details.yearStart?.toString(),
                      dub,
                    ]),
                    style: TextStyle(
                      fontSize: context.sp(17),
                      color: Nocturne.neutral400,
                    ),
                  ),
                  const Spacer(),
                  if (message != null)
                    _Notice(text: message!)
                  else if (resolving)
                    const _Notice(text: 'Шукаємо потік…')
                  else if (playback != null)
                    _Progress(playback: playback!, onSeek: onSeek),
                  SizedBox(height: context.px(14)),
                  if (context.pointer && playback != null)
                    _PointerBar(playback: playback!, onTogglePlay: onTogglePlay)
                  else
                    Text(
                      canSwitchDub
                          ? 'OK пауза  ·  ←→ перемотати 10 с  ·  ↓ озвучка  ·  ⌫ назад'
                          : 'OK пауза  ·  ←→ перемотати 10 с  ·  ⌫ назад',
                      style: TextStyle(
                        fontSize: context.sp(14),
                        color: Nocturne.neutral600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: context.sp(20), color: Nocturne.neutral300),
  );
}

/// The scrubber, driven straight off the playback rather than off a cubit —
/// it changes every frame and nothing else needs to know.
class _Progress extends StatelessWidget {
  const _Progress({required this.playback, this.onSeek});

  final Playback playback;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: playback,
      builder: (context, value, _) {
        final duration = value.duration;
        final fraction = duration.inMilliseconds == 0
            ? 0.0
            : value.position.inMilliseconds / duration.inMilliseconds;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!value.isPlaying) ...[
              Text(
                'ПАУЗА',
                style: TextStyle(
                  fontSize: context.sp(14),
                  letterSpacing: context.px(3),
                  color: context.accentSoft,
                ),
              ),
              SizedBox(height: context.px(10)),
            ],
            Row(
              children: [
                Text(
                  timecode(value.position),
                  style: TextStyle(
                    fontSize: context.sp(16),
                    color: Nocturne.neutral300,
                  ),
                ),
                SizedBox(width: context.px(16)),
                Expanded(
                  child: _Scrubber(
                    duration: duration,
                    onSeek: onSeek,
                    child: Stack(
                      children: [
                        Container(
                          height: context.px(4),
                          decoration: BoxDecoration(
                            color: Nocturne.neutral800,
                            borderRadius: BorderRadius.circular(context.px(2)),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: fraction.clamp(0.0, 1.0),
                          child: Container(
                            height: context.px(4),
                            decoration: BoxDecoration(
                              color: context.accent,
                              borderRadius: BorderRadius.circular(
                                context.px(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: context.px(16)),
                Text(
                  timecode(duration),
                  style: TextStyle(
                    fontSize: context.sp(16),
                    color: Nocturne.neutral300,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The scrubber, where a pointer can put the film.
///
/// Wraps the bar rather than replacing it: with a remote it adds nothing and
/// costs nothing, and the drawing above stays one description of the progress
/// rather than two that have to agree.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.duration, required this.child, this.onSeek});

  final Duration duration;
  final ValueChanged<Duration>? onSeek;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onSeek = this.onSeek;
    // A live stream has no end, so there is nowhere to aim.
    if (onSeek == null || duration == Duration.zero) return child;

    void seekTo(Offset local, Size size) {
      if (size.width <= 0) return;
      final fraction = (local.dx / size.width).clamp(0.0, 1.0);
      onSeek(duration * fraction);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => seekTo(details.localPosition, size),
            // Dragging along it scrubs, which is what a pointer expects and
            // what a remote has no way to ask for.
            onHorizontalDragUpdate: (details) =>
                seekTo(details.localPosition, size),
            child: Padding(
              // The bar is four pixels tall and nobody can hit that. The
              // padding is the target; the line stays as thin as it looks.
              padding: EdgeInsets.symmetric(vertical: context.px(12)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// What a pointer gets instead of the line about which key does what.
class _PointerBar extends StatelessWidget {
  const _PointerBar({required this.playback, this.onTogglePlay});

  final Playback playback;
  final VoidCallback? onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: playback,
      builder: (context, state, _) => Row(
        children: [
          _RoundButton(
            icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
            label: state.isPlaying ? 'Пауза' : 'Грати',
            onSelect: onTogglePlay,
          ),
          SizedBox(width: context.px(12)),
          const Spacer(),
          // Absent on a box, which is already the whole screen and has no
          // window to grow out of.
          if (Fullscreen.available)
            _RoundButton(
              icon: Fullscreen.active
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              label: 'На весь екран',
              onSelect: Fullscreen.toggle,
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.icon, required this.label, this.onSelect});

  final IconData icon;
  final String label;
  final VoidCallback? onSelect;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onSelect,
          child: Container(
            width: context.px(46),
            height: context.px(46),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered
                  ? context.accent.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.35),
              border: Border.all(
                color: _hovered ? context.accent : Nocturne.neutral700,
                width: context.px(1),
              ),
            ),
            child: Icon(
              widget.icon,
              size: context.px(24),
              color: Nocturne.text,
            ),
          ),
        ),
      ),
    );
  }
}
