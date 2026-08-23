import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'install_prompt.dart';

InstallPrompt installPromptForPlatform() => WebInstallPrompt();

/// The browser's own "install this app" offer, caught and held.
///
/// A page cannot ask to be installed. It can only wait for `beforeinstallprompt`
/// — which Chromium fires when *it* decides the page qualifies — cancel the
/// banner it would otherwise draw itself, and keep the event so that a button
/// in the interface can spend it later.
///
/// The service worker and the manifest that make the offer possible at all are
/// already there: Flutter registers `flutter_service_worker.js` from
/// `web/flutter_bootstrap.js`, and `web/manifest.json` is what names the app
/// and asks for a standalone window.
class WebInstallPrompt implements InstallPrompt {
  WebInstallPrompt() {
    web.window.addEventListener(
      'beforeinstallprompt',
      (web.Event event) {
        // Without this the browser draws its own bar wherever it likes. Taking
        // it over is the price of putting the offer on our own screen.
        event.preventDefault();
        _event = event as _BeforeInstallPromptEvent;
        _available.value = true;
      }.toJS,
    );

    // Fires when it actually goes in — by our button or by the browser's own
    // menu, which stays available whatever this screen does.
    web.window.addEventListener(
      'appinstalled',
      ((web.Event _) {
        _event = null;
        _available.value = false;
      }).toJS,
    );
  }

  final ValueNotifier<bool> _available = ValueNotifier(false);
  _BeforeInstallPromptEvent? _event;

  @override
  ValueListenable<bool> get available => _available;

  @override
  Future<bool> show() async {
    final event = _event;
    if (event == null) return false;

    event.prompt();
    final choice = await event.userChoice.toDart;
    // Spent either way: the browser will not accept the same event twice, and
    // a button that silently does nothing the second time is worse than one
    // that has gone.
    _event = null;
    _available.value = false;
    return choice.outcome == 'accepted';
  }
}

/// The event Chromium fires. Not in `package:web` — it is not a standard, which
/// is also why Firefox and Safari never send it.
@JS()
extension type _BeforeInstallPromptEvent(JSObject _) implements JSObject {
  external void prompt();

  external JSPromise<_InstallChoice> get userChoice;
}

@JS()
extension type _InstallChoice(JSObject _) implements JSObject {
  external String get outcome;
}
