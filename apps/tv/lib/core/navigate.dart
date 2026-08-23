import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'nav_tab.dart';
import 'web_history.dart';

/// Opening a screen, on a machine that has an address bar and on one that does
/// not.
///
/// On a box a screen is *pushed*: there is a stack, BACK unwinds it, and the
/// route that opened stays underneath waiting to be returned to. Nothing about
/// that is visible to anybody, and it is the right model for a remote.
///
/// In a browser it is wrong twice over. `push` records an imperative route and
/// deliberately leaves the address alone, so every screen read `/`: nothing
/// could be linked to, a reload always landed on the home screen, and the
/// browser's own Back stepped out of a stack the interface still believed in —
/// which is how a section came back with its tab underlined and a way-back
/// strip pointing at nothing.
///
/// So on the web every screen is a location instead, and the browser's history
/// *is* the stack — which is the one stack a person can already see, press
/// Back on, and share a link out of.
Future<T?> openRoute<T extends Object?>(
  BuildContext context,
  String location, {
  Object? extra,
}) {
  if (!kIsWeb) return GoRouter.of(context).push<T>(location, extra: extra);

  GoRouter.of(context).go(location, extra: extra);
  // Nothing to await: `go` has no result, and the screen that called this is
  // disposed on the way out and rebuilt on the way back, so a caller that used
  // to refresh itself after the pop returns re-reads on build instead.
  return Future<T?>.value(null);
}

/// The way back out of whatever is showing.
///
/// Three answers, in order, because there are three ways to have got here:
/// something was pushed and can be popped; the browser has a step of its own
/// history to take; or there is neither, and the way out is home.
void closeRoute(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
    return;
  }
  if (kIsWeb && canGoBackInHistory()) {
    goBackInHistory();
    return;
  }
  if (router.state.matchedLocation != NavTab.home.path) {
    router.go(NavTab.home.path);
  }
}
