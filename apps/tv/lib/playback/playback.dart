import 'package:flutter/widgets.dart';

/// Everything the screens ask about a video that is playing.
///
/// Deliberately smaller than what any one library offers: this is the whole
/// surface five player screens actually use, and keeping it to that is what
/// makes a second implementation a day's work rather than a rewrite.
@immutable
class PlaybackState {
  const PlaybackState({
    this.isReady = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.aspectRatio = 16 / 9,
    this.error,
  });

  /// Whether there is a picture yet. Nothing else here means anything until
  /// this is true.
  final bool isReady;

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;

  /// Zero for a live stream, which has no end to seek to.
  final Duration duration;

  final double aspectRatio;

  /// What went wrong, in whatever words the platform used. `null` while it
  /// has not.
  final String? error;

  bool get isLive => duration == Duration.zero;

  PlaybackState copyWith({
    bool? isReady,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? aspectRatio,
    String? error,
  }) => PlaybackState(
    isReady: isReady ?? this.isReady,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.isReady == isReady &&
      other.isPlaying == isPlaying &&
      other.isBuffering == isBuffering &&
      other.position == position &&
      other.duration == duration &&
      other.aspectRatio == aspectRatio &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    isReady,
    isPlaying,
    isBuffering,
    position,
    duration,
    aspectRatio,
    error,
  );
}

/// One video, and the few things a screen does to it.
///
/// The reason this exists rather than a `VideoPlayerController` passed around:
/// `video_player` supports `android ios macos web` and no Linux, and on the web
/// it hands the URL to a `<video>` element, which in Chrome has no HLS decoder
/// at all — every stream in this app is HLS. So the browser needs a different
/// implementation, and a Raspberry Pi will need a third. This is the seam they
/// meet at.
abstract class Playback extends ValueNotifier<PlaybackState> {
  Playback() : super(const PlaybackState());

  /// Opens the source and waits for a first frame's worth of information.
  ///
  /// Puts the reason in [PlaybackState.error] rather than throwing: a failed
  /// stream is an ordinary outcome here — the next provider gets tried — and
  /// every caller would otherwise wrap this in the same try.
  Future<void> load();

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration to);

  /// The picture. Sized by whoever mounts it; this fills what it is given.
  Widget view();
}
