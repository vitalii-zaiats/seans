import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/labels.dart';
import '../../../theme/nocturne.dart';

/// The top of the home screen when nothing is being promoted.
///
/// A clock over slow shapes mixed from the chosen accent. Nothing here is
/// fetched and nothing is advertised — which is the point: a banner is
/// somebody else's artwork filling a third of the screen every time the box is
/// turned on, and not everybody wants that in their living room.
class ClockHero extends StatefulWidget {
  const ClockHero({super.key});

  @override
  State<ClockHero> createState() => _ClockHeroState();
}

class _ClockHeroState extends State<ClockHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;
  late Timer _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Ninety seconds a lap: slow enough that it never asks to be looked at,
    // which is the difference between a background and a distraction. It also
    // never settles, so a widget test around this must pump a duration rather
    // than wait for quiet.
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 90),
    )..repeat();

    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.px(420),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => CustomPaint(
                painter: _Blobs(
                  turn: _drift.value,
                  accent: context.accent,
                  ground: context.ground,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: context.px(80)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clockLabel(_now),
                  style: TextStyle(
                    fontSize: context.sp(120),
                    height: 1,
                    fontWeight: FontWeight.w300,
                    color: Nocturne.text,
                  ),
                ),
                SizedBox(height: context.px(10)),
                Text(
                  dateLabel(_now),
                  style: TextStyle(
                    fontSize: context.sp(20),
                    letterSpacing: context.px(4),
                    color: Nocturne.neutral600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four soft circles drifting on their own cycles.
///
/// Mixed from the accent rather than painted in it: at full strength this
/// would be a colour field behind white text, and the point is a background
/// that the clock sits on rather than fights.
class _Blobs extends CustomPainter {
  const _Blobs({
    required this.turn,
    required this.accent,
    required this.ground,
  });

  /// 0–1, one full lap.
  final double turn;
  final Color accent;
  final Color ground;

  /// Each blob has its own radius, opacity and speed, so they never line up
  /// into a pattern somebody can start predicting.
  static const _blobs =
      <(double dx, double dy, double radius, double alpha, double speed)>[
        (0.72, 0.30, 0.55, 0.30, 1),
        (0.88, 0.72, 0.40, 0.22, -0.7),
        (0.55, 0.85, 0.35, 0.16, 1.4),
        (0.35, 0.20, 0.30, 0.12, -1.1),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    for (final (dx, dy, radius, alpha, speed) in _blobs) {
      final angle = turn * 2 * pi * speed;
      final centre = Offset(
        size.width * (dx + 0.05 * cos(angle)),
        size.height * (dy + 0.09 * sin(angle)),
      );
      final extent = size.shortestSide * radius;

      canvas.drawCircle(
        centre,
        extent,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: alpha),
              accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: extent)),
      );
    }
  }

  @override
  bool shouldRepaint(_Blobs old) =>
      old.turn != turn || old.accent != accent || old.ground != ground;
}
