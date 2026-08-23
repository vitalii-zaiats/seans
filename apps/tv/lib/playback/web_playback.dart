import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'playback.dart';

/// hls.js, as much of it as this needs.
@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls();

  /// Whether the browser has Media Source Extensions, which is what hls.js
  /// builds on. Everything since IE does.
  external static bool isSupported();

  external void loadSource(String url);
  external void attachMedia(web.HTMLMediaElement media);
  external void destroy();
  external void on(String event, JSFunction listener);
}

/// [Playback] for a browser, which has no HLS decoder and every stream here is
/// HLS.
///
/// A `<video>` element given an `.m3u8` answers `MEDIA_ERR_SRC_NOT_SUPPORTED`
/// in Chrome — there is no such decoder and `video_player` adds none. hls.js
/// reads the playlist itself and feeds the element through Media Source
/// Extensions, which Chrome does have. Safari decodes HLS natively, so there it
/// is handed the URL directly and hls.js never loads.
///
/// The element is a platform view rather than something Flutter paints. That
/// means it sits in its own layer above the canvas — which is also why the
/// controls drawn over it are Flutter's and land on top only because they are
/// later in the stack.
class WebPlayback extends Playback {
  WebPlayback.network(Uri url, {Map<String, String> headers = const {}})
    : _url = url.toString() {
    // Headers are not forgotten, they are impossible: a `<video>` element
    // sends what the browser decides and nothing else. What the box puts in
    // `Referer` the proxy has to put back, which is why it carries its own.
    _register();
  }

  final String _url;

  late final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = false
    ..controls = false
    // Without this iOS Safari takes the video fullscreen the moment it plays.
    ..setAttribute('playsinline', 'true')
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'contain'
    ..style.backgroundColor = 'transparent';

  _Hls? _hls;
  late final String _viewType = 'playback-${_nextId++}';
  static int _nextId = 0;

  /// Completed by the first `loadedmetadata`, or by whatever went wrong first.
  final _opened = Completer<void>();

  final _listeners = <(String, JSFunction)>[];

  void _register() {
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );
  }

  void _listen(String event, void Function(web.Event) handler) {
    final callback = handler.toJS;
    _video.addEventListener(event, callback);
    _listeners.add((event, callback));
  }

  @override
  Future<void> load() async {
    _listen('loadedmetadata', (_) {
      _publish();
      if (!_opened.isCompleted) _opened.complete();
    });
    _listen('durationchange', (_) => _publish());
    _listen('timeupdate', (_) => _publish());
    _listen('playing', (_) => _publish());
    _listen('play', (_) => _publish());
    _listen('pause', (_) => _publish());
    _listen('waiting', (_) => _publish());
    _listen('error', (_) {
      _fail(_elementError());
    });

    // hls.js first, and the order is the whole fix. `canPlayType` is not a
    // promise: Chrome answers `maybe` to `application/vnd.apple.mpegurl` and
    // then fails the element with `MEDIA_ERR_SRC_NOT_SUPPORTED`, because it
    // has no such decoder. Asking it first is how this shipped broken once.
    // Where hls.js runs at all it is the answer; native support is the
    // fallback, for iOS Safari, which has no Media Source Extensions.
    if (_hlsAvailable) {
      final hls = _Hls()
        ..attachMedia(_video)
        ..loadSource(_url);
      _hls = hls;
      // hls.js reports what the element cannot: a playlist that would not
      // parse, or a network error behind a request the element never made.
      hls.on(
        'hlsError',
        ((JSAny _, JSObject data) {
          if (data.getProperty<JSBoolean>('fatal'.toJS).toDart) {
            _fail('Потік не відкрився');
          }
        }).toJS,
      );
    } else if (_playsHlsItself) {
      _video.src = _url;
    } else {
      _fail('Цей браузер не програє HLS');
      return;
    }

    // A stream that never answers must not leave the screen spinning for ever;
    // the screens above treat an error as "try the next provider".
    await _opened.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => _fail('Потік не відповідає'),
    );
  }

  /// Whether the element will decode HLS on its own.
  ///
  /// Only consulted once hls.js has been ruled out, because the answer is
  /// unreliable in the direction that matters: Chrome says `maybe` and cannot.
  /// Where it is both true and reached — iOS Safari — it is the better path,
  /// since it decodes in hardware.
  bool get _playsHlsItself =>
      _video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;

  bool get _hlsAvailable => globalContext.has('Hls') && _Hls.isSupported();

  String _elementError() {
    final code = _video.error?.code;
    return switch (code) {
      // The one that brought us here, and the only one worth naming.
      4 => 'Браузер не програє цей формат',
      2 => 'Мережа обірвалася',
      3 => 'Потік пошкоджений',
      _ => 'Відео не відкрилося',
    };
  }

  void _fail(String message) {
    value = value.copyWith(error: message);
    if (!_opened.isCompleted) _opened.complete();
  }

  void _publish() {
    final duration = _video.duration;
    value = PlaybackState(
      isReady: _video.readyState >= 1,
      isPlaying: !_video.paused && !_video.ended,
      // `readyState` below HAVE_FUTURE_DATA means it has stopped to fetch.
      isBuffering: _video.readyState < 3 && !_video.paused,
      position: _seconds(_video.currentTime),
      // Live has no end: hls.js reports `Infinity`, and a `<video>` with
      // nothing loaded reports NaN. Both mean the same thing to the screens.
      duration: duration.isFinite ? _seconds(duration) : Duration.zero,
      aspectRatio: _video.videoHeight == 0
          ? 16 / 9
          : _video.videoWidth / _video.videoHeight,
      error: value.error,
    );
  }

  static Duration _seconds(num value) =>
      Duration(milliseconds: (value * 1000).round());

  @override
  Future<void> play() async {
    try {
      await _video.play().toDart;
    } on Object {
      // Autoplay with sound is refused unless the browser is sure a person
      // asked for it. Muted always plays, and a picture with the sound off is
      // better than a black rectangle — the screens show the state, so the
      // owner can turn it back on.
      _video.muted = true;
      try {
        await _video.play().toDart;
      } on Object {
        _fail('Браузер не дав почати відтворення');
      }
    }
    _publish();
  }

  @override
  Future<void> pause() async {
    _video.pause();
    _publish();
  }

  @override
  Future<void> seekTo(Duration to) async {
    _video.currentTime = to.inMilliseconds / 1000;
    _publish();
  }

  @override
  Widget view() => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    for (final (event, callback) in _listeners) {
      _video.removeEventListener(event, callback);
    }
    _listeners.clear();
    _hls?.destroy();
    // Not just `pause()`: an element left with a source keeps its buffer and,
    // on some browsers, keeps fetching. Emptying the source is what actually
    // lets go.
    _video
      ..pause()
      ..removeAttribute('src')
      ..load();
    super.dispose();
  }
}
