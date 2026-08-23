import 'playback.dart';

/// The browser implementation, as seen from a build that is not a browser.
///
/// `web_playback.dart` reaches for `dart:js_interop`, `dart:ui_web` and
/// `package:web`, none of which exist off the web — so the import is
/// conditional and this stands in. Nothing calls it: the same condition that
/// picks this file picks `VideoPlayback` beside it.
class WebPlayback extends Playback {
  WebPlayback.network(Uri url, {Map<String, String> headers = const {}}) {
    throw UnsupportedError('WebPlayback is for the browser');
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration to) async {}

  @override
  Never view() => throw UnsupportedError('WebPlayback is for the browser');
}
