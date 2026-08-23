import 'package:flutter/foundation.dart';

/// Whether this build can be installed onto the machine it is running on, and
/// the way to ask.
///
/// Only a browser can answer yes. Everywhere else the app *is* installed — it
/// arrived as an APK or a desktop bundle — so the whole idea is a no-op rather
/// than a missing feature, which is why the absent one below returns a
/// notifier that never fires instead of throwing.
abstract interface class InstallPrompt {
  /// True once the browser has offered. It is the browser's decision and its
  /// timing: Chrome fires when it decides the page qualifies, Firefox and
  /// Safari never do, and a copy that is already installed does not either.
  ///
  /// A listenable rather than a getter because it becomes true *after* the
  /// screen is built, and often a second or two after.
  ValueListenable<bool> get available;

  /// Show the browser's own install dialog. Answers true if it was accepted.
  ///
  /// Usable once: the event can only be spent on a single prompt, and asking
  /// again needs the browser to offer again.
  Future<bool> show();
}

/// What every platform that is already installed uses.
class AbsentInstallPrompt implements InstallPrompt {
  const AbsentInstallPrompt();

  @override
  ValueListenable<bool> get available => _never;

  @override
  Future<bool> show() async => false;

  static final _never = ValueNotifier(false);
}
