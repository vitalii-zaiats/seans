import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'playlist.dart';
import 'proxy_url.dart';

/// A development proxy: forwards what a browser will not, and serves the build.
///
/// Both halves in one server, and that is the point — with the page and its
/// requests on the same origin there is no cross-origin request left to refuse,
/// so nothing depends on the proxy getting its `Access-Control-Allow-Origin`
/// exactly right. The header is sent anyway, for the case of a page served from
/// somewhere else.
///
/// This is a development tool. It will forward a request to any host it is
/// given, which is fine on a laptop and is an open relay on a public address —
/// so it binds to the loopback interface unless told otherwise.
class CorsProxy {
  CorsProxy({
    this.port = 8080,
    this.root,
    this.address,
    this.onLog,
    this.defaultReferer,
    this.defaultAgent,
    HttpClient? client,
  }) : _client = client ?? (HttpClient()..userAgent = null);

  /// Where the built web app is, if this is also serving it.
  final Directory? root;

  final int port;

  /// What to bind to. Loopback by default: see the class comment.
  final InternetAddress? address;

  /// Where a line about each request goes. `null` keeps it quiet.
  final void Function(String line)? onLog;

  /// What to send as `Referer` and `User-Agent` when the request did not say.
  ///
  /// A page can name them per request through [ProxyUrl.refererHeader] — but a
  /// `<video>` element and the HLS segments it goes on to fetch by itself
  /// cannot set a header at all, and those are exactly the requests a CDN
  /// checks. Without a default here the picture is the one thing on the page
  /// that does not load.
  final String? defaultReferer;
  final String? defaultAgent;

  final HttpClient _client;
  HttpServer? _server;

  /// The address the browser should be pointed at, once [start] has returned.
  Uri get url => Uri.parse('http://${_server?.address.host}:${_server?.port}');

  /// What a rewritten playlist points back at.
  ///
  /// Empty, which makes every rewritten address root-relative and so correct
  /// from whatever host the page was actually opened on — including the box's
  /// address on the local network, which this server does not know.
  static const _publicBase = '';

  Future<void> start() async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _server = server;
    unawaited(_serve(server));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _client.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // One bad request must not take the server with it.
      unawaited(
        _handle(request).catchError((Object error) async {
          _log('${request.method} ${request.uri} — $error');
          await _fail(request, HttpStatus.badGateway, '$error');
        }),
      );
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _allowCrossOrigin(request.response);

    // The browser asks before sending anything with a header it considers
    // worth asking about — which includes the two this proxy relies on.
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final upstream = ProxyUrl.decode(request.uri.toString());
    if (upstream != null) {
      await _forward(request, upstream);
      return;
    }

    await _static(request);
  }

  Future<void> _forward(HttpRequest request, Uri upstream) async {
    _log('${request.method} $upstream');

    final outgoing = await _client.openUrl(request.method, upstream);
    // Redirects are followed here rather than handed back, because a 302 to
    // another host would send the browser off this origin and straight back
    // into the wall this exists to get around.
    outgoing.followRedirects = true;
    outgoing.maxRedirects = 5;

    _copyRequestHeaders(request, outgoing, upstream);

    // `Range` matters: a video element asks for a byte window and a proxy that
    // swallowed it would make every seek fetch the file from the start. It
    // rides along in the headers above; this is the body.
    await outgoing.addStream(request);
    final incoming = await outgoing.close();

    final response = request.response..statusCode = incoming.statusCode;
    _copyResponseHeaders(incoming, response);

    if (looksLikePlaylist(
      contentType: incoming.headers.contentType?.mimeType,
      path: upstream.path,
    )) {
      // Small enough to hold, and it has to be read to be useful: an HLS
      // playlist names the next request, and an absolute name in it would send
      // the player straight off this origin.
      final body = await incoming.transform(const Utf8Decoder()).join();
      response.write(rewritePlaylist(body, base: _publicBase));
      await response.close();
      return;
    }

    await incoming.pipe(response);
  }

  void _copyRequestHeaders(
    HttpRequest from,
    HttpClientRequest to,
    Uri upstream,
  ) {
    from.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_neverForwarded.contains(lower)) return;
      // The page's stand-ins for the headers it is not allowed to set.
      if (lower == ProxyUrl.refererHeader || lower == ProxyUrl.agentHeader) {
        return;
      }
      for (final value in values) {
        to.headers.add(name, value);
      }
    });

    // Point the request at the host it is actually going to, not at the proxy.
    to.headers.set(HttpHeaders.hostHeader, upstream.authority);

    final referer =
        from.headers.value(ProxyUrl.refererHeader) ?? defaultReferer;
    if (referer != null) to.headers.set(HttpHeaders.refererHeader, referer);

    final agent = from.headers.value(ProxyUrl.agentHeader) ?? defaultAgent;
    if (agent != null) to.headers.set(HttpHeaders.userAgentHeader, agent);
  }

  void _copyResponseHeaders(HttpClientResponse from, HttpResponse to) {
    from.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_neverForwarded.contains(lower)) return;
      // The upstream's own CORS answer is the one being replaced.
      if (lower.startsWith('access-control-')) return;

      // Replace rather than append. A Dart response is not born empty — it
      // carries `x-content-type-options` from the server's own defaults — and
      // adding the upstream's copy on top of that sends the header twice.
      // Duplicates are not always harmless: two values in one CORS header is
      // what a browser reads as none at all.
      to.headers.removeAll(name);
      for (final value in values) {
        to.headers.add(name, value);
      }
    });

    // Content-length arrives via the loop above but the body may be recoded on
    // the way out, so let the server work it out again.
    to.headers.removeAll(HttpHeaders.contentLengthHeader);
    _allowCrossOrigin(to);
  }

  void _allowCrossOrigin(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      // Without this a player cannot read `Content-Range` off its own response
      // and gives up on seeking.
      ..set('Access-Control-Expose-Headers', '*');
  }

  /// The built web app, if this server was given one.
  Future<void> _static(HttpRequest request) async {
    final root = this.root;
    if (root == null) {
      await _fail(request, HttpStatus.notFound, 'nothing is served here');
      return;
    }

    final relative = Uri.decodeComponent(request.uri.path);
    final target = _within(root, relative);
    // Outside the directory being served, which is never a screen and never a
    // file: refused outright, and no falling back to the app.
    if (target == null) {
      await _fail(request, HttpStatus.notFound, 'no such file');
      return;
    }

    final file = _existing(target) ?? _appFor(root, relative);
    if (file == null) {
      await _fail(request, HttpStatus.notFound, 'no such file');
      return;
    }

    request.response.headers.contentType = _typeOf(file.path);
    await file.openRead().pipe(request.response);
  }

  /// A single-page app owns every address below its root: `/catalog` and
  /// `/title/matrica` are screens, not files, and only the app knows that.
  /// Without this a reload anywhere but `/` is a 404 and the addresses are
  /// decoration.
  ///
  /// Only for a request that looks like navigation. A missing script or image
  /// must still say so — answering those with a page of HTML turns a broken
  /// build into a blank screen with nothing in the log.
  File? _appFor(Directory root, String path) {
    if (_looksLikeAFile(path)) return null;
    return _existing(root.absolute.uri.normalizePath().resolve('index.html'));
  }

  /// [path] resolved inside [root], or `null` when it lands outside.
  ///
  /// The containment check is the whole job: `..` in a request path is how a
  /// static server hands out the machine's private keys.
  Uri? _within(Directory root, String path) {
    final base = root.absolute.uri.normalizePath();
    final target = base
        .resolve(path.startsWith('/') ? path.substring(1) : path)
        .normalizePath();
    return target.toString().startsWith(base.toString()) ? target : null;
  }

  /// The file at [target], the directory's index, or `null` for neither.
  File? _existing(Uri target) {
    final file = File.fromUri(target);
    if (file.existsSync()) return file;

    if (Directory.fromUri(target).existsSync()) {
      final index = File.fromUri(target.resolve('index.html'));
      if (index.existsSync()) return index;
    }
    return null;
  }

  /// Whether the request is for an asset rather than a screen.
  ///
  /// An extension on the last segment is the whole test, and it is enough:
  /// every address this app uses is made of words.
  bool _looksLikeAFile(String path) => path.split('/').last.contains('.');

  ContentType _typeOf(String path) {
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'ico' => ContentType('image', 'x-icon'),
      'ttf' => ContentType('font', 'ttf'),
      'otf' => ContentType('font', 'otf'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }

  Future<void> _fail(HttpRequest request, int status, String message) async {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.text
        ..write(message);
      await request.response.close();
    } on StateError {
      // The response was already going out when this went wrong.
    }
  }

  void _log(String line) => onLog?.call(line);

  /// Headers that describe one hop and mean nothing on the next.
  ///
  /// `host` is set separately; the rest belong to the connection between the
  /// browser and this server, and passing them on either confuses the upstream
  /// or promises an encoding this server is not going to produce.
  static const _neverForwarded = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'host',
    'content-length',
  };
}
