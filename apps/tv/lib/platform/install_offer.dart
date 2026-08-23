import 'install_prompt.dart';

/// The browser's install offer, for whoever wants to draw it.
///
/// Assigned once in `main`, deliberately: the event this waits for arrives
/// moments after the page loads and is never repeated, so a listener that
/// waited for a screen to be built would already have missed it.
///
/// Settable for the same reason [platformBox] is — a test can hand in its own
/// without going anywhere near a browser.
InstallPrompt installPrompt = const AbsentInstallPrompt();
