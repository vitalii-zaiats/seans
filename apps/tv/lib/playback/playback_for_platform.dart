import 'package:flutter/foundation.dart';

import 'playback.dart';
import 'video_playback.dart';
import 'web_playback_absent.dart'
    if (dart.library.js_interop) 'web_playback.dart';

/// The playback implementation for wherever this is running.
///
/// Chosen here and nowhere else, the same way `box_for_platform.dart` chooses
/// the platform half. The screens take a [Playback] and do not care which one
/// they got.
///
/// `video_player` supports `android ios macos web`, but on the web it hands the
/// URL to a `<video>` element — and Chrome has no HLS decoder, which is every
/// stream in this app. So the browser gets its own implementation rather than
/// the shared one, and a Raspberry Pi will one day get a third.
Playback playbackFor(Uri url, {Map<String, String> headers = const {}}) =>
    kIsWeb
    ? WebPlayback.network(url, headers: headers)
    : VideoPlayback.network(url, headers: headers);

/// A file on one of the box's own drives.
///
/// There is no browser case: a web build has no drives to read, and the screen
/// that opens one is not there.
Playback playbackForFile(String path) => VideoPlayback.file(path);
