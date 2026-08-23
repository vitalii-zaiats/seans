import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/box_for_platform.dart';

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
}

/// The one place in the app that watches the keyboard globally.
///
/// Two things need a press that nothing else will see. The focus ring waits
/// for the first arrow, and the first arrow can land on any screen — including
/// the wizard, which is outside the shell. And the idle screen has to know
/// somebody is there, which the shell cannot learn from its own key handler:
/// while a film is playing the player answers every press, so the shell heard
/// silence and dropped the screensaver over a film somebody was watching with
/// the remote in their hand.
///
/// `HardwareKeyboard` sees a press before the focus tree divides it up. This
/// **never consumes** anything: it only watches.
abstract final class RemoteActivity {
  /// Starts watching. Called once from `main`.
  static void watch() => HardwareKeyboard.instance.addHandler(_onKey);

  /// Rings on every press, whoever ends up answering it.
  static Listenable get onKeyPress => _pressed;

  static final _pressed = _Bell();

  /// The keys that mean "I am steering with the keyboard".
  ///
  /// Not OK or Enter: those activate whatever is already focused, and somebody
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
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event is KeyDownEvent && _steering.contains(event.logicalKey)) {
        Dpad.used.value = true;
      }
      _pressed.ring();
    }
    // Never consumed. Returning true here would swallow every key in the app,
    // which is the opposite of the point.
    return false;
  }
}

/// A `Listenable` with nothing to read — only the fact that something happened.
class _Bell extends ChangeNotifier {
  void ring() => notifyListeners();
}
