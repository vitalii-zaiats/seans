/// Filling the screen, for whichever platform this is.
///
/// The same shape as `box_for_platform.dart`: chosen once, at one seam, and
/// absent rather than broken where it means nothing.
library;

export 'fullscreen_absent.dart'
    if (dart.library.js_interop) 'fullscreen_web.dart';
