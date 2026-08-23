import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Filling the window, which only a browser can be asked for.
///
/// The whole document goes fullscreen rather than the `<video>` element. Asking
/// the element instead hands the browser its own controls and its own escape
/// key handling, and the picture is a platform view — everything Flutter paints
/// over it, the scrubber included, would be left behind in the page.
abstract final class Fullscreen {
  static bool get available => true;

  static bool get active => web.document.fullscreenElement != null;

  /// The request only succeeds inside a gesture the browser believes a person
  /// made, and it refuses quietly rather than throwing something readable —
  /// so a refusal leaves the picture as it was and says nothing.
  static Future<void> toggle() async {
    try {
      if (active) {
        await web.document.exitFullscreen().toDart;
      } else {
        await web.document.documentElement?.requestFullscreen().toDart;
      }
    } on Object {
      // Refused, or the browser has no fullscreen at all.
    }
  }
}
