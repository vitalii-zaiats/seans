import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One camera, as somebody typed it in.
@immutable
class Camera {
  const Camera({required this.name, required this.url});

  final String name;

  /// `rtsp://user:pass@192.168.1.64:554/Streaming/Channels/101`, or whatever
  /// the camera's own manual says. Typed rather than discovered: every vendor
  /// spells the path differently, and guessing at one would be guessing.
  final String url;

  /// Whether the player can be expected to take it.
  ///
  /// RTSP is what a camera speaks and what ExoPlayer handles. An MJPEG stream
  /// over HTTP is the other common thing on a camera's web page, and nothing
  /// in this app can decode it — better said before the black screen.
  bool get isRtsp => url.toLowerCase().startsWith('rtsp://');

  /// The address without the password in it, for showing on a television that
  /// other people can see.
  String get safeUrl {
    final scheme = url.indexOf('://');
    if (scheme < 0) return url;

    // Credentials live in the authority — between `://` and the first `/`.
    // An `@` after that is part of the path, and masking up to it would hide
    // the host instead of the password.
    final start = scheme + 3;
    final slash = url.indexOf('/', start);
    final at = url.lastIndexOf('@', slash < 0 ? url.length : slash);
    if (at < start) return url;

    return '${url.substring(0, start)}•••${url.substring(at)}';
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  static Camera? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final url = json['url'] as String?;
    if (name == null || url == null || url.isEmpty) return null;
    return Camera(name: name, url: url);
  }

  @override
  bool operator ==(Object other) => other is Camera && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// The cameras this box knows about.
///
/// Nothing is discovered. ONVIF would find them on the network, but every
/// answer it gives still has to be turned into a stream path that differs per
/// vendor and per firmware — and none of that could be checked against a real
/// camera here, so it is not written.
class CameraStore {
  CameraStore(this._prefs) : _cameras = ValueNotifier(_read(_prefs));

  static const _key = 'cameras';

  static Future<CameraStore> open() async =>
      CameraStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final ValueNotifier<List<Camera>> _cameras;

  List<Camera> get cameras => _cameras.value;

  ValueListenable<List<Camera>> get listenable => _cameras;

  void dispose() => _cameras.dispose();

  bool get isEmpty => _cameras.value.isEmpty;

  Future<void> add(Camera camera) async {
    // The address is the identity: adding the same one twice would give two
    // tiles that are one camera.
    final next = [
      for (final existing in _cameras.value)
        if (existing.url != camera.url) existing,
      camera,
    ];
    await _write(next);
  }

  Future<void> remove(Camera camera) async {
    await _write([
      for (final existing in _cameras.value)
        if (existing.url != camera.url) existing,
    ]);
  }

  Future<void> clear() async {
    _cameras.value = const [];
    await _prefs.remove(_key);
  }

  Future<void> _write(List<Camera> cameras) async {
    _cameras.value = cameras;
    await _prefs.setStringList(_key, [
      for (final camera in cameras) jsonEncode(camera.toJson()),
    ]);
  }

  static List<Camera> _read(SharedPreferences prefs) {
    final raw = prefs.getStringList(_key) ?? const [];
    final cameras = <Camera>[];

    for (final line in raw) {
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          if (Camera.fromJson(json) case final camera?) cameras.add(camera);
        }
      } on FormatException {
        // A row written by an older build. Dropping it beats refusing to show
        // the rest.
      }
    }
    return cameras;
  }
}
