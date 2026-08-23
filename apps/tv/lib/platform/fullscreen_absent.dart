/// Filling the screen, where the platform is already filling it.
///
/// A box has no window to grow out of and no browser chrome to hide — the
/// launcher is the whole display and always was. So this answers "nothing to
/// do", and the button that would offer it is not drawn.
abstract final class Fullscreen {
  static bool get available => false;

  static bool get active => false;

  static Future<void> toggle() async {}
}
