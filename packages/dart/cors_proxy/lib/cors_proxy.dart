/// Addressing for the proxy, and nothing that touches a socket.
///
/// Kept apart from `server.dart` on purpose: the browser build imports this to
/// work out where to send a request, and importing `dart:io` — which the server
/// half needs — would take the whole web build down with it.
library;

export 'src/playlist.dart';
export 'src/proxy_url.dart';
