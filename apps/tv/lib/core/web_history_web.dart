import 'package:web/web.dart' as web;

/// Whether the browser has a step of its own to take.
///
/// `history.length` counts this tab's whole history, the page we arrived on
/// included — so anything above one means there is somewhere to go back to.
/// It cannot tell *our* entries from the page somebody visited before, which
/// is why the caller checks the router first.
bool canGoBackInHistory() => web.window.history.length > 1;

void goBackInHistory() => web.window.history.back();
