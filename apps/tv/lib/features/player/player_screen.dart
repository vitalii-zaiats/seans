import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hls/hls.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/remote/back.dart';
import '../../core/remote/focus_area.dart';
import '../../data/library_store.dart';
import '../../data/stream_resolver.dart';
import '../../data/web_proxy.dart';
import '../../playback/playback.dart';
import '../../playback/playback_for_platform.dart';
import '../../theme/nocturne.dart';
import '../../widgets/poster_image.dart';
import 'player_cubit.dart';
import 'widgets/playback_picker.dart';
import 'widgets/player_controls.dart';

/// Playback, grown out of the home screen.
///
/// The route lands on a blurred still of the title's own backdrop and stays
/// there while the stream is found, so the transition never shows a black gap
/// — the video simply fades in over the picture that was already on screen.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.details,
    required this.season,
    this.episode,
    this.resumeAt,
    super.key,
  });

  final ContentDetails details;
  final Season season;
  final int? episode;
  final Duration? resumeAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Playback? _playback;
  Timer? _hideControls;
  Timer? _saveProgress;
  bool _controlsVisible = true;
  bool _videoVisible = false;
  bool _picking = false;
  String? _playbackError;

  /// What the current controller was built for, so a change of episode can be
  /// told from a change of voice-over — one starts from the beginning, the
  /// other picks up where it left off.
  int? _playingSeason;
  int? _playingEpisode;

  /// Where to start. Set from the caller at first, then from the position a
  /// dub switch interrupted — swapping voice-overs should not lose the place.
  late Duration? _resumeAt = widget.resumeAt;

  /// The last save is the one that matters — where somebody stopped watching —
  /// and it happens in `dispose`, by which point this element is deactivated
  /// and reading an ancestor out of the tree throws. So every exit from a film
  /// ended in `Looking up a deactivated widget's ancestor is unsafe` and the
  /// final position was never written: the list went on offering the place the
  /// last fifteen-second tick had saved.
  late final LibraryStore _library;

  /// How long the controls stay up after the last button press.
  static const _controlsLinger = Duration(seconds: 4);
  static const _seekStep = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryStore>();
    // A television should not dim or sleep mid-film, and the system bars have
    // no business over a picture.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _saveProgress?.cancel();
    unawaited(_persistProgress());
    _playback?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _start(ResolvedStream stream, {String? url}) async {
    // A dub switch arrives here with something already playing.
    final previous = _playback;
    if (previous != null) {
      setState(() {
        _playback = null;
        _videoVisible = false;
      });
      previous.dispose();
    }

    final playback = playbackFor(
      // The chosen quality where there is one, and the playlist that lets the
      // player choose where there is not.
      Uri.parse(WebProxy.forUrl(url ?? stream.url)!),
      headers: const {
        // The CDN checks these the same way the embed page does. In a browser
        // they go nowhere — a `<video>` element sends what the browser decides
        // and nothing else — which is why the proxy carries its own copies.
        'Referer': 'https://kinostrain.com/',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 12; BRAVIA) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    );

    await playback.load();

    final failure = playback.value.error;
    if (failure != null) {
      // Disposed first and unconditionally: an unmounted screen still has to
      // let go of what it opened.
      playback.dispose();
      if (!mounted) return;
      setState(() => _playbackError = 'Потік не відкрився: $failure');
      return;
    }

    if (!mounted) {
      playback.dispose();
      return;
    }

    final playing = context.read<PlayerCubit>().state;
    _playingSeason = playing.seasonNumber;
    _playingEpisode = playing.episode;

    final resume = _resumeAt;
    if (resume != null &&
        resume > Duration.zero &&
        resume < playback.value.duration) {
      await playback.seekTo(resume);
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
      _videoVisible = true;
    });

    // Often enough that a power cut loses seconds rather than a film.
    _saveProgress?.cancel();
    _saveProgress = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_persistProgress()),
    );
  }

  Future<void> _persistProgress() async {
    final playback = _playback;
    if (playback == null || !playback.value.isReady) return;

    final progress = WatchProgress(
      slug: widget.details.slug,
      position: playback.value.position,
      duration: playback.value.duration,
      updatedAt: DateTime.now(),
      season: widget.season.number,
      episode: widget.episode,
    );

    // A film watched to the end leaves the rail rather than sitting at 99%.
    if (progress.isFinished) {
      await _library.clearProgress(widget.details.slug);
    } else if (progress.isStarted) {
      await _library.saveProgress(progress);
    }
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

  Future<void> _togglePlay() async {
    final playback = _playback;
    if (playback == null) return;

    if (playback.value.isPlaying) {
      await playback.pause();
      // A pause is a stopping point worth surviving a power cut.
      await _persistProgress();
    } else {
      await playback.play();
    }
    if (mounted) _showControls();
  }

  Future<void> _seek(Duration by) async {
    final playback = _playback;
    if (playback == null || !playback.value.isReady) return;

    final target = playback.value.position + by;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > playback.value.duration ? playback.value.duration : target);
    await playback.seekTo(clamped);
    _showControls();
  }

  /// Straight to a moment, which is what a pointer aims at. The arrows can
  /// only ask for a step, so [_seek] takes an offset and this takes a place.
  Future<void> _seekTo(Duration to) async {
    final playback = _playback;
    if (playback == null || !playback.value.isReady) return;

    await playback.seekTo(to);
    _showControls();
  }

  /// Shows the panel — season, episode and voice-over, whichever apply.
  void _openPicker() {
    final state = context.read<PlayerCubit>().state;
    if (!state.canSwitchDub &&
        !state.canSwitchSeason &&
        state.episodes.isEmpty) {
      _showControls();
      return;
    }
    // The panel is an area of its own, and the arbiter walks into it the
    // moment it is mounted — and puts focus back on the picture when it goes.
    // Nothing here asks for focus, and nothing here guards against the panel
    // and the player both answering the arrows: only one of them is on screen
    // under the ring at a time, which is the whole of the rule now.
    setState(() => _picking = true);
  }

  void _closePicker() {
    if (!_picking) return;
    setState(() => _picking = false);
  }

  /// Same shape as switching a voice-over: remember the moment, close the
  /// sheet, and let the listener reopen the video at the new address.
  void _chooseQuality(HlsVariant? variant) {
    _resumeAt = _playback?.value.position ?? _resumeAt;
    _closePicker();
    context.read<PlayerCubit>().selectQuality(variant);
    _showControls();
  }

  Future<void> _chooseDub(int index) async {
    // Come back to the same moment in the other voice-over.
    _resumeAt = _playback?.value.position ?? _resumeAt;

    _closePicker();
    await context.read<PlayerCubit>().selectDub(index);
    if (mounted) _showControls();
  }

  /// A different episode is a different film as far as position goes: bank
  /// what was watched of this one, then start the next from the beginning.
  Future<void> _chooseEpisode(int number) async {
    final cubit = context.read<PlayerCubit>();
    await _persistProgress();
    _resumeAt = null;
    _closePicker();
    await cubit.selectEpisode(number);
    if (mounted) _showControls();
  }

  /// The panel stays open across a season change: picking a season is half the
  /// choice, and the episode row underneath is the other half.
  Future<void> _chooseSeason(int number) async {
    final cubit = context.read<PlayerCubit>();
    await _persistProgress();
    _resumeAt = null;
    await cubit.selectSeason(number);
  }

  /// The arrows on a player are not a way round a screen: → is ten seconds,
  /// ↓ is the panel, and ↑ is "show me what is playing".
  bool _onMove(RemoteMove move) {
    switch (move) {
      case RemoteMove.right:
        unawaited(_seek(_seekStep));
      case RemoteMove.left:
        unawaited(_seek(-_seekStep));
      case RemoteMove.up:
        _showControls();
      case RemoteMove.down:
        _openPicker();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (previous, current) =>
          current.status.isSuccess &&
          current.stream != null &&
          // A quality change reopens the video at a different address, the
          // same way a dub switch does.
          (current.playingUrl != previous.playingUrl ||
              current.seasonNumber != _playingSeason ||
              current.episode != _playingEpisode),
      listener: (context, state) =>
          unawaited(_start(state.stream!, url: state.playingUrl)),
      child: Scaffold(
        backgroundColor: Colors.black,
        // A pointer has no keys to press, so moving it is the only way it
        // can say "I am here" — without this the controls fade after four
        // seconds and never come back.
        body: MouseRegion(
          onHover: context.pointer ? (_) => _showControls() : null,
          child: GestureDetector(
            // Clicking the picture is what a browser has instead of OK.
            onTap: context.pointer ? () => unawaited(_togglePlay()) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The picture and its controls: modal, because a film is not
                // somewhere the arrows should be able to wander out of, and
                // carrying `controls`, because here they are the transport.
                FocusArea(
                  modal: true,
                  landing: true,
                  controls: RemoteControls(
                    onMove: _onMove,
                    onSelect: () => unawaited(_togglePlay()),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AmbientBackdrop(details: widget.details),
                      if (_playback != null)
                        AnimatedOpacity(
                          opacity: _videoVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _playback!.value.aspectRatio,
                              child: _playback!.view(),
                            ),
                          ),
                        ),
                      BlocBuilder<PlayerCubit, PlayerState>(
                        builder: (context, state) => PlayerControls(
                          details: widget.details,
                          episode: state.episode,
                          playback: _playback,
                          onSeek: (to) => unawaited(_seekTo(to)),
                          onTogglePlay: () => unawaited(_togglePlay()),
                          visible: _controlsVisible || _playback == null,
                          resolving:
                              state.status.isLoading && _playbackError == null,
                          message: _playbackError ?? state.error,
                          dub: state.stream?.dub,
                          canSwitchDub:
                              state.canSwitchDub ||
                              state.canSwitchSeason ||
                              state.episodes.isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                ),
                // The panel beside the picture rather than inside it: which of
                // the two owns the remote is then a matter of where the ring
                // is, not of a flag the screen has to remember to check on
                // every key. Its own way out, so the hint that says "⌫ закрити"
                // is true in a browser and in a PWA window as well as on a box.
                if (_picking)
                  BackStop(
                    onBack: () {
                      _closePicker();
                      return BackAnswer.took;
                    },
                    child: FocusArea(
                      modal: true,
                      landing: true,
                      child: BlocBuilder<PlayerCubit, PlayerState>(
                        builder: (context, state) => PlaybackPicker(
                          state: state,
                          onSeason: _chooseSeason,
                          onEpisode: _chooseEpisode,
                          onDub: _chooseDub,
                          onQuality: _chooseQuality,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The title's own backdrop, blurred — what the crossfade lands on, and what
/// stays behind a film whose picture is narrower than the panel.
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.details});

  final ContentDetails details;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
          child: PosterImage(url: details.sliderUrl ?? details.posterUrl),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.ground.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
