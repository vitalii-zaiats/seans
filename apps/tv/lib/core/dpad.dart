import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../platform/box_for_platform.dart';

/// Whether anybody has driven this interface from a keyboard yet.
///
/// A television is focus-first: something is always ringed, because the remote
/// has no other way of saying where it is. A browser is pointer-first, and a
/// ring drawn before anybody has touched an arrow key is a highlight on a
/// button nobody chose — which is exactly what it looked like on first run.
///
/// So the ring waits for the first arrow or Tab. This is the same idea as CSS
/// `:focus-visible`, and it is only ever a question on a machine with a mouse:
/// on a box [used] starts true and stays there.
abstract final class Dpad {
  static final ValueNotifier<bool> used = ValueNotifier(platformBox.present);

  /// Starts watching. Called once from `main`.
  ///
  /// A global handler rather than a widget: the first arrow press can land on
  /// any screen, including ones that are not under the launcher shell, and a
  /// listener per screen would be a listener somebody forgets to add.
  static void watch() {
    if (used.value) return; // a box: nothing to wait for
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// The keys that mean "I am steering with the keyboard".
  ///
  /// Not OK or Enter: those activate whatever is already focused, and a person
  /// who clicked a tile and then pressed Enter has still not asked for a ring.
  // `final`, not `const`: `LogicalKeyboardKey` overrides `==`, and a constant
  // set may not hold anything that does.
  static final _steering = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.select,
  };

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && _steering.contains(event.logicalKey)) {
      used.value = true;
      // Once is enough — and this handler runs on every key press until it goes.
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    // Never consumed: this only watches. Returning true here would swallow
    // every arrow in the app, which is the opposite of the point.
    return false;
  }
}
