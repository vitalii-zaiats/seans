import '../../widgets/back_chip.dart';
import '../../platform/box_for_platform.dart';
import '../../core/remote/back.dart';
import '../../core/remote/focus_area.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../data/web_proxy.dart';
import '../../platform/fullscreen.dart';
import '../../playback/playback.dart';
import '../../playback/playback_for_platform.dart';
import '../../core/labels.dart';
import '../../data/iptv_store.dart';
import '../../theme/nocturne.dart';
import 'live_channel.dart';
import 'tv_cubit.dart';

/// Live television.
///
/// A separate screen from the film player on purpose. A broadcast has no
/// duration, nothing to seek through and no position worth remembering, so
/// almost every control on the other screen would be a lie here — and the
/// arrows mean something else entirely: the next channel, not the next ten
/// seconds.
class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({required this.channel, super.key});

  final LiveChannel channel;

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  Playback? _playback;
  Timer? _hideControls;

  late LiveChannel _channel = widget.channel;
  bool _controlsVisible = true;

  /// What is on and what follows, when the source has a guide.
  TvSchedule? _schedule;
  bool _opening = true;
  String? _error;

  /// Channel name and clock linger a little longer than the film player's
  /// controls: on live TV it is the only thing that says what you are watching.
  static const _controlsLinger = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_open(_channel));
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _playback?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _open(LiveChannel channel) async {
    final store = context.read<IptvStore>();
    final cubit = context.read<TvCubit>();
    final previous = _playback;
    setState(() {
      _channel = channel;
      _playback = null;
      _opening = true;
      _error = null;
      _schedule = null;
    });
    previous?.dispose();

    unawaited(store.rememberChannel(channel.id));
    // The guide is a separate request and nothing waits on it, so playback
    // starts while it is still in the air.
    unawaited(_loadSchedule(cubit, channel));

    // A playlist entry carries its URL; sweet.tv trades an id for one that
    // expires, so this is asked again on every open rather than remembered.
    final String url;
    try {
      url = await cubit.streamUrl(channel);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = error.message;
      });
      return;
    }

    // sweet.tv's stitching host allows any origin, so hls.js reads it in a
    // browser unaided — but a channel out of a public playlist is whatever
    // that list points at, and most of those name nobody. Through the proxy
    // when there is one; unchanged when there is not.
    final playback = playbackFor(Uri.parse(WebProxy.forUrl(url)!));
    await playback.load();
    final failure = playback.value.error;
    if (failure != null) {
      final error = failure;
      if (kDebugMode) debugPrint('live player: $url failed with $error');
      // Disposed first and unconditionally: an unmounted screen still has to
      // let go of what it opened.
      playback.dispose();
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = switch (channel) {
          // The commonest cause by far, and invisible without saying so.
          PlaylistChannel(isCleartext: true) =>
            'Канал віддається без шифрування, і система могла його '
                'заблокувати',
          PlaylistChannel() =>
            'Канал не відповідає — у публічних списках це звичайна річ',
          // A curated source that fails is worth more than a shrug: the
          // platform's own message is the only thing that says why.
          SweetLiveChannel() => 'Не вдалося відтворити цей канал',
        };
      });
      return;
    }

    if (!mounted) {
      playback.dispose();
      return;
    }

    await playback.play();

    // Going back during the awaits above unmounts this screen while nothing
    // holds the controller yet — `dispose()` finds `_controller` still null,
    // and the stream plays on with the screen gone.
    if (!mounted) {
      playback.dispose();
      return;
    }
    setState(() {
      _playback = playback;
      _opening = false;
    });
    _showControls();
  }

  Future<void> _loadSchedule(TvCubit cubit, LiveChannel channel) async {
    final schedule = await cubit.scheduleFor(channel);
    if (!mounted || schedule == null || _channel.id != channel.id) return;
    setState(() => _schedule = schedule);
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(_controlsLinger, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _switch(int step) {
    final next = context.read<TvCubit>().next(_channel, step: step);
    if (next == null) return;
    unawaited(_open(next));
  }

  /// Arrows change channel here. There is nothing to seek through, and a
  /// viewer who presses right expects the next channel, as on any TV.
  bool _onMove(RemoteMove move) {
    _switch(move.forward ? 1 : -1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // The screen is the control, so the area carries one and holds a node of
    // its own. The root `Focus` here used to have no node at all: once
    // anything else took focus there was nothing left to hand a press to, and
    // the channel keys went dead until the screen was left and reopened.
    return FocusArea(
      modal: true,
      landing: true,
      controls: RemoteControls(onMove: _onMove, onSelect: _showControls),
      child: Scaffold(
        backgroundColor: Colors.black,
        // A pointer has no keys, so moving it is the only way it can ask for
        // the controls back after they fade.
        body: MouseRegion(
          onHover: context.pointer ? (_) => _showControls() : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_playback != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _playback!.value.aspectRatio,
                    child: _playback!.view(),
                  ),
                ),
              _Overlay(
                channel: _channel,
                schedule: _schedule,
                visible: _controlsVisible || _playback == null,
                opening: _opening,
                error: _error,
                onRetry: () => _open(_channel),
              ),
              // Last, so it is on top of the overlay rather than under it, and
              // outside `_Overlay` because that one ignores every pointer.
              if (context.pointer && Fullscreen.available)
                Positioned(
                  right: context.px(40),
                  bottom: context.px(40),
                  child: _Fullscreen(visible: _controlsVisible),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one control a live channel has for a pointer.
///
/// There is nothing to seek — a live stream has no end — and pausing what is
/// being broadcast is a promise this cannot keep. Filling the window is the
/// whole of it.
class _Fullscreen extends StatefulWidget {
  const _Fullscreen({required this.visible});

  final bool visible;

  @override
  State<_Fullscreen> createState() => _FullscreenState();
}

class _FullscreenState extends State<_Fullscreen> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Tooltip(
          message: 'На весь екран',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => unawaited(Fullscreen.toggle()),
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
                  Fullscreen.active ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: context.px(24),
                  color: Nocturne.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.channel,
    required this.schedule,
    required this.visible,
    required this.opening,
    required this.error,
    required this.onRetry,
  });

  final LiveChannel channel;
  final TvSchedule? schedule;
  final bool visible;
  final bool opening;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0, 0.3, 0.6, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.px(60)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // A machine with a pointer needs something to click. A
                      // remote has BACK under a thumb; a PWA window has no
                      // browser Back at all, and the shell's way-back strip is
                      // hidden over a picture that goes edge to edge — so
                      // without this the only way out was a key nobody can see.
                      if (!platformBox.present) ...[
                        BackChip(onSelect: () => Back.requestFrom(context)),
                        SizedBox(width: context.px(20)),
                      ],
                      const _LiveBadge(),
                      SizedBox(width: context.px(16)),
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: context.sp(34),
                            fontWeight: FontWeight.w500,
                            color: Nocturne.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (channel.group != null) ...[
                    SizedBox(height: context.px(6)),
                    Text(
                      channel.group!,
                      style: TextStyle(
                        fontSize: context.sp(17),
                        color: Nocturne.neutral400,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (schedule != null) _Guide(schedule: schedule!),
                  if (opening)
                    Text(
                      'Вмикаємо…',
                      style: TextStyle(
                        fontSize: context.sp(20),
                        color: Nocturne.neutral300,
                      ),
                    )
                  else if (error != null)
                    _Failure(message: error!, onRetry: onRetry),
                  SizedBox(height: context.px(14)),
                  Text(
                    '←→ канал  ·  OK показати  ·  ⌫ назад',
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

/// What is on now, how far through it is, and what follows.
///
/// The one thing a broadcast has that a film does not: a position that is not
/// yours. A film's scrubber says where *you* are; this says where the schedule
/// is, and neither of those is something you can drag.
class _Guide extends StatefulWidget {
  const _Guide({required this.schedule});

  final TvSchedule schedule;

  @override
  State<_Guide> createState() => _GuideState();
}

class _GuideState extends State<_Guide> {
  late Timer _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Once a minute is enough for a bar that crosses in half an hour, and it
    // keeps a launcher that never closes from waking every second.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.schedule.onAt(_now);
    final next = widget.schedule.afterAt(_now);
    if (now == null && next == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: context.px(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (now != null) ...[
            Text(
              now.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: context.sp(22), color: Nocturne.text),
            ),
            SizedBox(height: context.px(8)),
            Row(
              children: [
                Text(
                  '${clockLabel(now.start)} – ${clockLabel(now.stop)}',
                  style: TextStyle(
                    fontSize: context.sp(15),
                    color: Nocturne.neutral500,
                  ),
                ),
                SizedBox(width: context.px(14)),
                SizedBox(
                  width: context.px(420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(context.px(2)),
                    child: Stack(
                      children: [
                        Container(
                          height: context.px(4),
                          color: Nocturne.neutral800,
                        ),
                        FractionallySizedBox(
                          widthFactor: now.progressAt(_now),
                          child: Container(
                            height: context.px(4),
                            color: context.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (next != null) ...[
            SizedBox(height: context.px(10)),
            Text(
              'Далі о ${clockLabel(next.start)} — ${next.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: context.sp(16),
                color: Nocturne.neutral500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where a film's scrubber would be. There is no position to draw, so this
/// says the one thing that is true instead.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.px(12),
        vertical: context.px(5),
      ),
      decoration: BoxDecoration(
        color: context.accentTint,
        border: Border.all(color: context.accent, width: context.px(1)),
        borderRadius: BorderRadius.circular(context.px(4)),
      ),
      child: Text(
        'НАЖИВО',
        style: TextStyle(
          fontSize: context.sp(13),
          letterSpacing: context.px(2),
          color: context.accentSoft,
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: context.px(22),
          color: Nocturne.neutral400,
        ),
        SizedBox(width: context.px(12)),
        Flexible(
          child: Text(
            '$message. ←→ перемкне на наступний.',
            style: TextStyle(
              fontSize: context.sp(19),
              color: Nocturne.neutral300,
            ),
          ),
        ),
      ],
    );
  }
}
