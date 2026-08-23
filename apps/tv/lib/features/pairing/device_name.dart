import 'package:flutter/foundation.dart';

/// What to call this box on somebody else's phone.
///
/// Deliberately not [currentPlatform] from `data/startup.dart`, though the two
/// look alike. That one answers "which of the four builds is this", and it is
/// sent to `/init` where the server matches it against release channels — so it
/// folds macOS in with linux, which is right there and wrong here. This one is
/// read by a person deciding whether the thing asking to be let in is the
/// television in their own living room, and macOS and Linux are not the same
/// answer to that question.
///
/// Coarse on purpose all the same. A real model name — `Mi Box S`, `SHIELD` —
/// would mean a `device_info_plus` dependency and a platform channel on every
/// target, to sharpen a label that only has to distinguish the two or three
/// boxes one household owns.
///
/// Never longer than 80 characters, which is what the server stores. Nothing
/// here comes close, and that is the point: the alternative was the
/// `User-Agent`, which is 117 characters of browser trivia on the web.
String describeThisDevice() {
  // `kIsWeb` first, and not out of caution: `dart:io` compiles for the web as a
  // stub whose members throw the moment they are touched, and
  // `defaultTargetPlatform` on the web reports the *host* OS — so a browser on
  // a Mac would call itself macOS and say nothing about being a browser.
  if (kIsWeb) return 'Браузер';

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android TV',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}
