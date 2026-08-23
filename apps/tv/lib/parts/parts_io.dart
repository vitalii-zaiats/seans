import 'dart:io' show Platform;

import 'package:go_router/go_router.dart';
import 'package:provider/single_child_widget.dart';

import '../platform/absent_box.dart';
import '../platform/android_box.dart';
import '../platform/box.dart';
import 'parts.dart';

/// A machine with a filesystem: an Android box, a desktop, a Raspberry Pi.
///
/// This is the only file that may name an Android-only package, and the reason
/// the web bundle is free of them is that the web build never compiles it.
///
/// The launcher half is still chosen at runtime inside here, because "not the
/// web" is not the same as "Android": a desktop build gets [AbsentBox] and
/// keeps the parts that are not the box's — which is exactly what let the same
/// screens run on a Pi.
final class NativeParts implements Parts {
  NativeParts();

  @override
  late final Box box = Platform.isAndroid
      ? const AndroidBox()
      : const AbsentBox();

  @override
  List<SingleChildWidget> providers() {
    if (!box.present) return const [];
    // Bindings for the sections a set-top box has. Added here as each is
    // ported; a desktop skips them because it has nothing behind them.
    return const [];
  }

  @override
  List<RouteBase> routes() {
    if (!box.present) return const [];
    return const [];
  }

  @override
  Future<void> dispose() async {}
}

Parts partsForPlatform() => NativeParts();
