import 'dart:convert';
import 'dart:io';

import 'package:cors_proxy/cors_proxy.dart';
import 'package:cors_proxy/server.dart';
import 'package:test/test.dart';

/// A stand-in upstream: answers with what it was asked, so a test can check
/// what actually arrived rather than what was meant to be sent.
Future<HttpServer> upstream({
  void Function(HttpRequest request)? answer,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (answer != null) {
      answer(request);
      await request.response.close();
      return;
    }
    request.response
      ..headers.contentType = ContentType.json
      ..headers.set('access-control-allow-origin', 'https://kinostrain.com')
      ..write(
        jsonEncode({
          'method': request.method,
          'path': request.uri.toString(),
          'host': request.headers.value('host'),
          'referer': request.headers.value('referer'),
          'agent': request.headers.value('user-agent'),
          'custom': request.headers.value('x-thing'),
        }),
      );
    await request.response.close();
  });
  return server;
}

void main() {
  late CorsProxy proxy;
  late HttpServer origin;
  late HttpClient client;

  setUp(() async {
    origin = await upstream();
    proxy = CorsProxy(port: 0);
    await proxy.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await proxy.stop();
    await origin.close(force: true);
  });

  Uri proxied(String path) => Uri.parse(
    ProxyUrl.encode(
      Uri.parse('http://${origin.address.host}:${origin.port}$path'),
      base: proxy.url.toString(),
    ),
  );

  Future<HttpClientResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    return request.close();
  }

  Future<Map<String, dynamic>> seenAt(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final response = await get(proxied(path), headers: headers);
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  test('it forwards the path and query as they were', () async {
    final seen = await seenAt('/api/content?season=2&q=%D0%B0');

    expect(seen['path'], '/api/content?season=2&q=%D0%B0');
    expect(seen['method'], 'GET');
  });

  test('the upstream is told its own host, not the proxy', () async {
    // A host header naming the proxy reaches a virtual host that does not
    // exist, and the answer is somebody else's default site.
    final seen = await seenAt('/');

    expect(seen['host'], '${origin.address.host}:${origin.port}');
  });

  test('it puts back the headers a browser refuses to send', () async {
    final seen = await seenAt(
      '/',
      headers: {
        ProxyUrl.refererHeader: 'https://kinostrain.com/',
        ProxyUrl.agentHeader: 'Mozilla/5.0 (BRAVIA)',
      },
    );

    expect(seen['referer'], 'https://kinostrain.com/');
    expect(seen['agent'], 'Mozilla/5.0 (BRAVIA)');
  });

  test('and does not pass on the stand-ins themselves', () async {
    final response = await get(
      proxied('/'),
      headers: {ProxyUrl.refererHeader: 'https://kinostrain.com/'},
    );
    final body = await response.transform(utf8.decoder).join();

    expect(body, isNot(contains(ProxyUrl.refererHeader)));
  });

  test('an ordinary header goes through untouched', () async {
    final seen = await seenAt('/', headers: {'x-thing': 'kept'});

    expect(seen['custom'], 'kept');
  });

  test('it answers with an origin the page may read', () async {
    final response = await get(proxied('/'));

    expect(response.headers.value('access-control-allow-origin'), '*');
  });

  test('replacing the upstream\'s own, rather than sending two', () async {
    // Two values in that header is the one thing a browser treats as no value
    // at all, and the request fails for a reason nothing reports.
    final response = await get(proxied('/'));

    expect(response.headers['access-control-allow-origin'], hasLength(1));
  });

  test('a preflight is answered without going upstream', () async {
    var reached = false;
    final watcher = await upstream(answer: (_) => reached = true);
    final request = await client.openUrl(
      'OPTIONS',
      Uri.parse(
        ProxyUrl.encode(
          Uri.parse('http://${watcher.address.host}:${watcher.port}/'),
          base: proxy.url.toString(),
        ),
      ),
    );
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.noContent);
    expect(reached, isFalse);
    await watcher.close(force: true);
  });

  test('a header the upstream sent once is sent on once', () async {
    // A Dart response already carries `x-content-type-options` before anything
    // is copied into it, so a proxy that appends sends everything twice.
    final strict = await upstream(
      answer: (request) =>
          request.response.headers.set('x-content-type-options', 'nosniff'),
    );
    final response = await get(
      Uri.parse('${proxy.url}/x/http/${strict.address.host}:${strict.port}/'),
    );
    await response.drain<void>();

    expect(response.headers['x-content-type-options'], ['nosniff']);
    await strict.close(force: true);
  });

  test('a status is passed through as it came', () async {
    final teapot = await upstream(
      answer: (request) => request.response.statusCode = 418,
    );
    final response = await get(
      Uri.parse(
        ProxyUrl.encode(
          Uri.parse('http://${teapot.address.host}:${teapot.port}/'),
          base: proxy.url.toString(),
        ),
      ),
    );
    await response.drain<void>();

    expect(response.statusCode, 418);
    await teapot.close(force: true);
  });

  test(
    'an upstream that is not there answers 502, and the proxy lives',
    () async {
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();

      final response = await get(
        Uri.parse('${proxy.url}/x/http/127.0.0.1:$port/'),
      );
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.badGateway);

      // Still serving.
      final after = await seenAt('/');
      expect(after['method'], 'GET');
    },
  );

  group('defaults', () {
    setUp(() async {
      await proxy.stop();
      proxy = CorsProxy(
        port: 0,
        defaultReferer: 'https://kinostrain.com/',
        defaultAgent: 'BRAVIA',
      );
      await proxy.start();
    });

    test('stand in for a request that cannot carry headers at all', () async {
      // A `<video>` element, and every HLS segment it fetches on its own.
      final seen = await seenAt('/stream.m3u8');

      expect(seen['referer'], 'https://kinostrain.com/');
      expect(seen['agent'], 'BRAVIA');
    });

    test('and give way to a request that names its own', () async {
      final seen = await seenAt(
        '/',
        headers: {ProxyUrl.refererHeader: 'https://elsewhere/'},
      );

      expect(seen['referer'], 'https://elsewhere/');
      expect(seen['agent'], 'BRAVIA', reason: 'the unnamed one still applies');
    });
  });

  group('serving the build', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cors_proxy_test');
      File('${root.path}/index.html').writeAsStringSync('<h1>launcher</h1>');
      File('${root.path}/main.dart.js').writeAsStringSync('console.log(1)');
      await proxy.stop();
      proxy = CorsProxy(port: 0, root: root);
      await proxy.start();
    });

    tearDown(() => root.deleteSync(recursive: true));

    Future<HttpClientResponse> fetch(String path) =>
        get(Uri.parse('${proxy.url}$path'));

    test('the root is the index', () async {
      final response = await fetch('/');

      expect(
        await response.transform(utf8.decoder).join(),
        '<h1>launcher</h1>',
      );
    });

    test('a script is served as one', () async {
      final response = await fetch('/main.dart.js');

      expect(response.headers.contentType?.mimeType, 'text/javascript');
    });

    test('an address below the root is the app, not a missing file', () async {
      // A single-page app owns every address under it. Without this a reload
      // on /catalog is a 404 and the addresses are decoration.
      final response = await fetch('/catalog/movie');

      expect(response.statusCode, HttpStatus.ok);
      expect(
        await response.transform(utf8.decoder).join(),
        '<h1>launcher</h1>',
      );
    });

    test('but a missing asset still says so', () async {
      // Answering a missing script with a page of HTML turns a broken build
      // into a blank screen with nothing in the log.
      final response = await fetch('/nope.js');
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.notFound);
    });

    test('nothing outside the directory it serves can be reached', () async {
      // The property that matters, tested against a real file rather than a
      // path that looks alarming: `..` is how a static server hands out the
      // machine's private keys.
      //
      // `HttpServer` normalises the dot segments away before any of this runs,
      // so the containment check is the second lock rather than the first —
      // which is exactly why it is worth having and worth testing.
      final secret = File(
        '${root.parent.path}/outside-${root.path.hashCode}.txt',
      )..writeAsStringSync('the machine\'s own business');
      addTearDown(secret.deleteSync);

      final response = await fetch('/../${secret.uri.pathSegments.last}');
      final body = await response.transform(utf8.decoder).join();

      expect(body, isNot(contains("machine's own business")));
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('and proxies at the same time', () async {
      final response = await get(
        Uri.parse(
          ProxyUrl.encode(
            Uri.parse('http://${origin.address.host}:${origin.port}/a'),
            base: proxy.url.toString(),
          ),
        ),
      );
      final body = await response.transform(utf8.decoder).join();

      expect(jsonDecode(body), containsPair('path', '/a'));
    });
  });
}
