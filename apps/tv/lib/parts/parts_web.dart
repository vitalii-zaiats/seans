import 'package:go_router/go_router.dart';
import 'package:provider/single_child_widget.dart';

import '../platform/absent_box.dart';
import '../platform/box.dart';
import 'parts.dart';

/// A browser tab.
///
/// Nothing here, and that is the whole point of the file: it names no
/// Android-only package and no box-only screen, so none of them is in the
/// bundle. Not hidden, not tree-shaken on a good day — absent.
///
/// What the web build keeps is everything that was never the box's: the home
/// screen, the catalogue, a title, search, television, the player.
final class WebParts implements Parts {
  const WebParts();

  @override
  Box get box => const AbsentBox();

  @override
  List<SingleChildWidget> providers() => const [];

  @override
  List<RouteBase> routes() => const [];

  @override
  Future<void> dispose() async {}
}

Parts partsForPlatform() => const WebParts();
