import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'playback.dart';

/// [Playback] over `video_player`, which is ExoPlayer on the box.
///
/// Everything this adds is translation: the screens ask a small fixed set of
/// questions and this answers them from `VideoPlayerValue`. What it does not
/// add is behaviour — quality selection, the viewport cap, RTSP — all of that
/// is ExoPlayer's and stays ExoPlayer's.
class VideoPlayback extends Playback {
  VideoPlayback.network(Uri url, {Map<String, String> headers = const {}})
    : _controller = VideoPlayerController.networkUrl(url, httpHeaders: headers);

  /// A file on one of the box's drives. Never reached on the web, where
  /// `dart:io` is a stub that throws the moment it is touched.
  VideoPlayback.file(String path)
    : _controller = VideoPlayerController.file(File(path));

  final VideoPlayerController _controller;

  @override
  Future<void> load() async {
    try {
      await _controller.initialize();
    } on Object catch (error) {
      value = value.copyWith(error: '$error');
      return;
    }
    _controller.addListener(_mirror);
    _mirror();
  }

  void _mirror() {
    final from = _controller.value;
    value = PlaybackState(
      isReady: from.isInitialized,
      isPlaying: from.isPlaying,
      isBuffering: from.isBuffering,
      position: from.position,
      duration: from.duration,
      aspectRatio: from.aspectRatio,
      error: from.errorDescription,
    );
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration to) => _controller.seekTo(to);

  @override
  Widget view() => VideoPlayer(_controller);

  @override
  void dispose() {
    _controller
      ..removeListener(_mirror)
      ..dispose();
    super.dispose();
  }
}
