import 'package:cors_proxy/cors_proxy.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sending a browser's requests somewhere it is allowed to read them from.
///
/// Two rules of a browser stand between the web build and every host this
/// talks to, and neither can be argued with from inside the page: a response
/// is unreadable unless the host names this exact origin, and `Referer`,
/// `Origin` and `User-Agent` are dropped from any request the page tries to
/// set them on. The catalogue names `https://kinostrain.com` and nothing else;
/// ashdi answers 400 to a request carrying neither of the headers it looks for.
///
/// So on the web every request goes to `packages/cors_proxy` instead, which is
/// not a browser and is bound by neither rule. Off the web nothing here does
/// anything at all — the calls stay in place, unconditional, and return what
/// they were given.
abstract final class WebProxy {
  /// Whether to route through the proxy, and where it is.
  ///
  /// Off unless asked for, because there is more than one way past a browser
  /// and the other one needs no proxy at all:
  ///
  /// ```bash
  /// # a browser told to stop checking, for a local look
  /// flutter run -d chrome --web-browser-flag=--disable-web-security
  ///
  /// # served by the proxy, which is the only way that works for anybody else
  /// flutter build web --dart-define=PROXY=same-origin
  /// dart run cors_proxy --root build/web --port 8731
  ///
  /// # the proxy on its own port, for a debug session
  /// flutter run -d chrome --dart-define=PROXY=http://127.0.0.1:8080
  /// ```
  ///
  /// Defaulting this on would be the worse mistake of the two: an app that
  /// insists on a proxy fails with nothing on screen when it is not running,
  /// and the reason is invisible. Going direct fails the same way it always
  /// did, which is a failure the browser explains in its own console.
  static const _setting = String.fromEnvironment('PROXY');

  /// `same-origin` means the proxy is serving this page, so every proxied
  /// address is relative — and correct from whatever host the page was opened
  /// on, including the box's address on the local network.
  static const _sameOrigin = 'same-origin';

  static String get base => _setting == _sameOrigin ? '' : _setting;

  /// Whether requests are being redirected at all.
  static bool get inUse => kIsWeb && _setting.isNotEmpty;

  /// [url] as the browser should ask for it.
  ///
  /// For an image or a video source, where the request is made by the browser
  /// itself and there is no client to wrap.
  static String? forUrl(String? url) {
    if (!inUse || url == null) return url;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return url;
    return ProxyUrl.encode(parsed, base: base);
  }

  /// [client] with every request rewritten on its way out.
  ///
  /// Returns the client untouched off the web, so a caller can wrap
  /// unconditionally.
  static http.Client wrap(http.Client client) =>
      inUse ? _ProxyClient(client) : client;
}

/// Rewrites the address, and carries the forbidden headers under names the
/// browser has no opinion about.
class _ProxyClient extends http.BaseClient {
  _ProxyClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final proxied = http.Request(
      request.method,
      Uri.parse(ProxyUrl.encode(request.url, base: WebProxy.base)),
    );

    request.headers.forEach((name, value) {
      // A browser drops these silently rather than refusing them, which is
      // worse: the request goes out looking like nothing in particular and the
      // host answers 400 with no hint as to why. The proxy puts them back.
      switch (name.toLowerCase()) {
        case 'referer':
          proxied.headers[ProxyUrl.refererHeader] = value;
        case 'user-agent':
          proxied.headers[ProxyUrl.agentHeader] = value;
        default:
          proxied.headers[name] = value;
      }
    });

    if (request is http.Request) proxied.bodyBytes = request.bodyBytes;
    proxied.followRedirects = request.followRedirects;

    return _inner.send(proxied);
  }

  @override
  void close() => _inner.close();
}
