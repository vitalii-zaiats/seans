import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../nav_tab.dart';

/// The one way out of whatever is showing.
///
/// **`LogicalKeyboardKey.goBack` is bound nowhere, and this is the only place
/// that says so.** Android's BACK arrives twice — once as that key event, and
/// once as the platform's own pop through [LauncherBackDispatcher] — and a
/// screen that answered the key made one press two steps: out of the player,
/// and then out of the section behind it. On a box, where this app is the home
/// screen, that second step reads as being thrown back to the start; anywhere
/// else it closes the app. Measured on the Television_1080p emulator: with the
/// key ignored, the platform's pop on its own lands exactly one step out.
///
/// Two things can ask to go back — the platform, and the ⌫ / Esc keys the
/// arbiter takes — and both arrive at [Back.request]. There is no third: a
/// screen says what BACK means by mounting a [BackStop], not by watching keys.
enum BackAnswer {
  /// Handled here. Nothing further happens.
  took,

  /// Not mine — ask whoever is behind me.
  pass,

  /// Nothing to do, and the platform may have the press: on a box that is the
  /// way out of the app, which is not a thing a screen should be able to take
  /// away.
  floor,
}

/// "While I am on screen, BACK means this."
///
/// A declaration rather than a key handler, so a screen cannot accidentally
/// hold two of them, and so the answer is the same however the press arrived.
class BackStop extends StatefulWidget {
  const BackStop({required this.onBack, required this.child, super.key});

  final BackAnswer Function() onBack;

  final Widget child;

  @override
  State<BackStop> createState() => _BackStopState();
}

class _BackStopState extends State<BackStop> {
  @override
  void initState() {
    super.initState();
    Back._stops.add(this);
  }

  @override
  void dispose() {
    Back._stops.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Where every way back ends up.
abstract final class Back {
  static final _stops = <_BackStopState>[];

  /// Answers one press. `false` means "nobody here wanted it" — on Android
  /// that hands it to the platform, which is how a launcher's first screen
  /// still lets somebody out of the app.
  ///
  /// The browser's own history is deliberately not consulted. It used to be,
  /// between the pop and the walk home, and it was dead code: every route in
  /// this app is nested under `/`, so `canPop()` is already true wherever that
  /// branch could have been reached — and `history.length` counts the pages
  /// somebody visited *before* the app as well, so on the one location where
  /// it was reachable it would have walked them out of it.
  static bool request(GoRouter router) {
    // Innermost first: a panel opened over a player answers before the player.
    for (final stop in _stops.reversed.toList()) {
      switch (stop.widget.onBack()) {
        case BackAnswer.took:
          return true;
        case BackAnswer.floor:
          return false;
        case BackAnswer.pass:
          continue;
      }
    }

    if (router.canPop()) {
      router.pop();
      return true;
    }

    // The floor of the stack. On a box home is where BACK lands from
    // everywhere, and one press gets there rather than unwinding a section at
    // a time.
    if (router.state.matchedLocation != NavTab.home.path) {
      router.go(NavTab.home.path);
      return true;
    }

    return false;
  }

  /// The same, for a widget that has a context and no router in hand.
  static void requestFrom(BuildContext context) => request(GoRouter.of(context));
}

/// The single door the platform's BACK comes through on Android.
///
/// Not a widget, and that is the point: a second one cannot be added from a
/// screen, so there is no way to grow a second answer to one press. The
/// router's own delegate is never asked — [Back.request] does the popping, so
/// the key and the platform cannot disagree about what one press means.
class LauncherBackDispatcher extends RootBackButtonDispatcher {
  LauncherBackDispatcher({required this.router});

  final GoRouter router;

  @override
  Future<bool> didPopRoute() async => Back.request(router);
}
