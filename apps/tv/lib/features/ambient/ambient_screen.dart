import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../core/remote/back.dart';
import '../../core/remote/focus_area.dart';
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

  /// Slow drift, so the clock does not sit on the same pixels all night.
  Alignment _drift = Alignment.center;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A remote has buttons and nothing else, so a key was the whole
    // interaction. In a browser the thing in somebody's hand is a mouse: they
    // click the clock, nothing happens, and the screen looks frozen rather
    // than idle. A screensaver wakes on movement, and so does this.
    final wakesOnPointer = !platformBox.present;

    // A modal area with controls of its own: it takes the whole remote while
    // it is up, holds a node so there is always something for a press to land
    // on, and hands focus back to whatever it covered when it goes.
    //
    // Any button at all comes back — that is the whole interaction, and the
    // shell hears every press through `RemoteActivity`, including the ones
    // that never reach a widget. This is what stops the arrows leaking into
    // the screen underneath in the meantime.
    return BackStop(
      onBack: () {
        widget.onWake();
        return BackAnswer.took;
      },
      child: FocusArea(
        modal: true,
        landing: true,
        controls: RemoteControls(
          onMove: (_) {
            widget.onWake();
            return true;
          },
          onSelect: widget.onWake,
        ),
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
      ),
    );
  }
}
