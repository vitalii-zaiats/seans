import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../platform/box_for_platform.dart';
import '../../theme/nocturne.dart';

/// What the launcher becomes after a while of nothing.
///
/// A television left on its home screen burns the same pixels for hours, so
/// after the idle timeout the interface gets out of the way and leaves the
/// clock, the date, and what was half-watched.
class AmbientScreen extends StatefulWidget {
  const AmbientScreen({
    required this.resumeTitle,
    required this.onWake,
    super.key,
  });

  /// `The Last Meridian · 42%`, or `null` when nothing is part-watched.
  final String? resumeTitle;

  final VoidCallback onWake;

  @override
  State<AmbientScreen> createState() => _AmbientScreenState();
}

class _AmbientScreenState extends State<AmbientScreen> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  /// Held rather than requested by `autofocus`.
  ///
  /// `autofocus` only lands if nothing in the scope is focused yet, and by the
  /// time this appears something always is — a tile on the screen underneath.
  /// So the request was quietly dropped, every key went to that tile, and the
  /// one instruction on screen ("press any button") did nothing.
  final _node = FocusNode(debugLabel: 'ambient');

  /// Slow drift, so the clock does not sit on the same pixels all night.
  Alignment _drift = Alignment.center;

  @override
  void initState() {
    super.initState();
    // After the first frame: taking focus during a build is an assertion, and
    // this is mounted into a Stack that is being built right now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });

    _timer = Timer.periodic(const Duration(seconds: 20), (tick) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        _drift = Alignment(
          (tick.tick % 7 - 3) * 0.06,
          (tick.tick % 5 - 2) * 0.06,
        );
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A remote has buttons and nothing else, so a key was the whole
    // interaction. In a browser the thing in somebody's hand is a mouse: they
    // click the clock, nothing happens, and the screen looks frozen rather
    // than idle. A screensaver wakes on movement, and so does this.
    final wakesOnPointer = !platformBox.present;

    return Focus(
      focusNode: _node,
      // Any button at all comes back — that is the whole interaction.
      onKeyEvent: (_, _) {
        widget.onWake();
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onHover: wakesOnPointer ? (_) => widget.onWake() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onWake,
          // Mounted straight into the shell's Stack, so unlike every other screen
          // it has no Scaffold above it — and without a Material ancestor every
          // Text falls back to Flutter's yellow, double-underlined debug style.
          child: Material(
            color: context.ground,
            child: AnimatedAlign(
              alignment: _drift,
              duration: const Duration(seconds: 8),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    clockLabel(_now),
                    style: TextStyle(
                      fontSize: context.sp(140),
                      height: 1,
                      fontWeight: FontWeight.w300,
                      color: Nocturne.text,
                    ),
                  ),
                  SizedBox(height: context.px(14)),
                  Text(
                    dateLabel(_now),
                    style: TextStyle(
                      fontSize: context.sp(20),
                      letterSpacing: context.px(4),
                      color: Nocturne.neutral600,
                    ),
                  ),
                  if (widget.resumeTitle != null) ...[
                    SizedBox(height: context.px(56)),
                    Text(
                      'ПРОДОВЖИТИ ПЕРЕГЛЯД',
                      style: TextStyle(
                        fontSize: context.sp(13),
                        letterSpacing: context.px(3),
                        color: context.accent,
                      ),
                    ),
                    SizedBox(height: context.px(10)),
                    Text(
                      widget.resumeTitle!,
                      style: TextStyle(
                        fontSize: context.sp(22),
                        color: Nocturne.neutral300,
                      ),
                    ),
                  ],
                  SizedBox(height: context.px(60)),
                  Text(
                    wakesOnPointer
                        ? 'НАТИСНІТЬ КЛАВІШУ АБО РУХНІТЬ МИШЕЮ'
                        : 'НАТИСНІТЬ БУДЬ-ЯКУ КНОПКУ',
                    style: TextStyle(
                      fontSize: context.sp(13),
                      letterSpacing: context.px(3),
                      color: Nocturne.neutral800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
