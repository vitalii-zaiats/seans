import 'package:go_router/go_router.dart';
import 'package:provider/single_child_widget.dart';

import '../platform/box.dart';

/// What a platform contributes beyond the screens every platform has.
///
/// The launcher already had a seam for the machine underneath — [Box], with an
/// absent implementation for anything that is not a set-top box. This is the
/// same idea moved one level up, to the composition root, and it exists for a
/// reason the old one could not solve.
///
/// [Box] kept the *screens* from knowing about Android. It did not keep the
/// **build** from containing it: `app.dart` constructed an F-Droid client and
/// `router.dart` imported every box-only screen, unconditionally, so a web
/// build shipped a catalogue of installable APKs and a file browser it could
/// never open. Tree shaking cannot help — the code was reachable.
///
/// So the choice is made by conditional import instead, and a platform's half
/// is only ever named by the file for that platform. `parts_web.dart` has never
/// heard of F-Droid, and what a compiler has not been shown it cannot ship.
///
/// A platform that has none of this returns nothing from all three, which is
/// already how this app expresses absence: no routes means the sections are not
/// merely hidden but unreachable, and `NavTab.needsBox` keeps them off the row.
abstract interface class Parts {
  /// The machine underneath.
  Box get box;

  /// Bindings only this platform can make — an APK downloader, a LAN scanner.
  ///
  /// Handed to `MultiRepositoryProvider` above the router, so a box-only screen
  /// reads its dependencies off the context exactly like every other screen.
  List<SingleChildWidget> providers();

  /// Routes only this platform has.
  ///
  /// Nested under the home path, which is where they were: `/apps`, `/storage`,
  /// `/cameras`, `/fun`.
  List<RouteBase> routes();

  /// Releases whatever the bindings above hold open.
  Future<void> dispose();
}
