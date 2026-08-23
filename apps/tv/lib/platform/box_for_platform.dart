import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'absent_box.dart';
import 'android_box.dart';
import 'box.dart';

/// The platform half for wherever this is running.
///
/// Chosen once, here. Everywhere else takes a [Box] and does not care which one
/// it got — which is what lets the same screens run on a set-top box and on a
/// Raspberry Pi, growing the launcher parts only where they exist.
///
/// Settable so a test can hand in its own without going near a method channel,
/// and so a platform that grows its own half later has one line to change.
Box platformBox = _forThisPlatform();

/// `kIsWeb` is checked first and that is not caution.
///
/// `dart:io` compiles for the web as a stub whose members throw the moment
/// they are touched — so the build succeeds and the app dies on its first
/// frame, which is a worse failure than not building at all. Reading
/// `Platform` at all has to be guarded.
Box _forThisPlatform() {
  if (kIsWeb) return const AbsentBox();
  return Platform.isAndroid ? const AndroidBox() : const AbsentBox();
}
