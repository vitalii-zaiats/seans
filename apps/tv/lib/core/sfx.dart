import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One noise the interface can make.
///
/// The file and the gain both come from `tools/sfx-generator`, which mixes the
/// whole set together and writes the result to `out/manifest.json`. The gains
/// there are a *hierarchy*, not per-file taste — they are what keeps a click
/// from sitting louder than a section change on the same television — so they
/// are copied here rather than re-guessed.
enum SfxCue {
  /// The generator calls this one "екранна клавіатура пошуку", and it is the
  /// shortest sound in the set at 13 ms. It is used here for every select,
  /// which is broader than that: `select.wav` (300 ms) is what the set intends
  /// for activating a card, and it would be a much heavier sound on a row of
  /// posters somebody is walking through.
  tap('sfx/key_tap.wav', 0.30),

  /// "Упор у край ряду" — a dull 174 Hz thud meaning "there is nothing further
  /// this way", 59 ms. Used here for changing section along the top bar.
  navEdge('sfx/nav_edge.wav', 0.45),

  /// A television joined to an account by QR. Two voices that start apart in
  /// the stereo image and arrive together, which is the event rather than just
  /// a pleasant cadence — 1.05 s, and 200 KB against the others' one or five,
  /// because it is stereo and a second long. It plays once per pairing.
  paired('sfx/paired.wav', 0.75);

  const SfxCue(this.asset, this.gain);

  /// Relative to `assets/`, which is where `AssetSource` starts looking.
  final String asset;

  /// `manifest.json`'s recommended gain for this clip.
  final double gain;

  void play() => Sfx._play(this);
}

/// The noises the interface makes.
///
/// **Fire and forget, always.** Nothing here is awaited by a caller and no
/// failure here reaches one: a select that opened a screen has done its job
/// whether or not a 1 KB wav also played. On the web the first sound before any
/// gesture is refused outright by the browser, and a select *is* a gesture —
/// but a focus change is not, so anything added later must survive being
/// silently denied.
///
/// A singleton rather than something injected. It has no state worth faking, no
/// test in this app reads it, and threading a provider through sixteen widgets
/// to reach `Focusable` — which is the point of the thing — would be a lot of
/// wiring for a click.
abstract final class Sfx {
  /// A player per clip, created at most once each.
  ///
  /// Per clip rather than one shared: `play` swaps the source, so two cues
  /// alternating on one player would tear down and reload each other's file
  /// on every press. They are a kilobyte apiece.
  ///
  /// A `Future` rather than the player, so two presses landing together await
  /// the same construction instead of racing to build two — the second of which
  /// would leak a platform handle, and on Android a `SoundPool` slot rather
  /// than a Dart object.
  static final Map<SfxCue, Future<AudioPlayer>> _players = {};

  /// Set false and every cue becomes a no-op. Nothing toggles it yet — it is
  /// here so the settings screen has something to bind to when somebody wants
  /// the box quiet.
  static bool enabled = true;

  /// Kept as its own name because it is the overwhelmingly common one.
  static void tap() => SfxCue.tap.play();

  static void _play(SfxCue cue) {
    if (!enabled) return;
    unawaited(_fire(cue));
  }

  static Future<AudioPlayer> _create() async {
    final player = AudioPlayer();
    // `stop`, not the default `release`: releasing tears the source down after
    // every play, so the next press pays to load the file again. Keeping it
    // costs one decoded kilobyte.
    await player.setReleaseMode(ReleaseMode.stop);
    return player;
  }

  static Future<void> _fire(SfxCue cue) async {
    try {
      final player = await _players.putIfAbsent(cue, _create);
      // `play` on a player already playing restarts it, which is what a
      // held-down key should sound like — one sound per press, from the top.
      await player.play(AssetSource(cue.asset), volume: cue.gain);
    } catch (error) {
      // A box with no audio route, a browser that refused, a platform whose
      // plugin did not register. None is worth a crash or a log line on every
      // press — the interface goes quiet and still works.
      //
      // It is also worth knowing that this is where a silent app ends up: a
      // stale `.dart_tool` build directory once left the web plugin
      // unregistered, and every press failed here with a
      // `MissingPluginException` that nothing on screen could show.
      if (kDebugMode) debugPrint('sfx: ${cue.asset} did not play — $error');
    }
  }

  /// Releases every player. For a box shutting the app down for good.
  static Future<void> dispose() async {
    final pending = List.of(_players.values);
    _players.clear();
    for (final one in pending) {
      try {
        await (await one).dispose();
      } catch (_) {
        // Disposing something that never finished being created is not a
        // failure anybody can act on.
      }
    }
  }
}
