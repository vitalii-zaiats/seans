import 'package:cors_proxy/cors_proxy.dart';
import 'package:test/test.dart';

void main() {
  group('encode', () {
    test('puts the upstream in the path', () {
      expect(
        ProxyUrl.encode(Uri.parse('https://kinostrain.com/api/content')),
        '/x/https/kinostrain.com/api/content',
      );
    });

    test('keeps the query', () {
      expect(
        ProxyUrl.encode(Uri.parse('https://host/search?q=матриця&limit=20')),
        contains('?q=%D0%BC'),
      );
    });

    test('keeps the port', () {
      expect(
        ProxyUrl.encode(Uri.parse('http://192.168.1.10:8080/stream.m3u8')),
        '/x/http/192.168.1.10:8080/stream.m3u8',
      );
    });

    test('a bare host still gets a path', () {
      // Otherwise the result is `/x/https/host`, and the decoder cannot tell
      // the authority from the first path segment.
      expect(ProxyUrl.encode(Uri.parse('https://host')), '/x/https/host/');
    });

    test('an absolute base goes in front', () {
      expect(
        ProxyUrl.encode(
          Uri.parse('https://host/a'),
          base: 'http://127.0.0.1:8080',
        ),
        'http://127.0.0.1:8080/x/https/host/a',
      );
    });

    test('percent-encoding in the path survives', () {
      // A signed stream URL carries `%2F` inside a parameter, and decoding it
      // turns it into a path separator and breaks the signature.
      final url = Uri.parse('https://host/hls/a%2Fb/index.m3u8?token=x%2Fy');
      expect(ProxyUrl.encode(url), contains('a%2Fb'));
      expect(ProxyUrl.encode(url), contains('token=x%2Fy'));
    });
  });

  group('decode', () {
    test('reads back what encode wrote', () {
      for (final url in [
        'https://kinostrain.com/api/content/matrix?season=2',
        'http://host:8080/a/b/c.ts',
        'https://host/',
        'https://host/hls/a%2Fb/index.m3u8?token=x%2Fy',
      ]) {
        final encoded = ProxyUrl.encode(Uri.parse(url));
        expect(ProxyUrl.decode(encoded).toString(), url, reason: encoded);
      }
    });

    test('a relative segment resolves to the same host', () {
      // This is why the upstream lives in the path. An HLS playlist names its
      // parts relatively and nothing rewrites them.
      final playlist = Uri.parse(
        ProxyUrl.encode(Uri.parse('https://host/hls/720/index.m3u8')),
      );
      final segment = playlist.resolve('seg-1.ts');

      expect(
        ProxyUrl.decode(segment.toString()),
        Uri.parse('https://host/hls/720/seg-1.ts'),
      );
    });

    test('an unproxied path is not one', () {
      expect(ProxyUrl.decode('/index.html'), isNull);
      expect(ProxyUrl.decode('/'), isNull);
      expect(ProxyUrl.decode('/xyz/https/host/a'), isNull);
    });

    test('refuses a scheme that is not the web', () {
      // Forwarding `file:` would read the machine running the proxy.
      expect(ProxyUrl.decode('/x/file/etc/passwd'), isNull);
      expect(ProxyUrl.decode('/x/ftp/host/a'), isNull);
    });

    test('refuses a missing host', () {
      expect(ProxyUrl.decode('/x/https//path'), isNull);
      expect(ProxyUrl.decode('/x/https'), isNull);
      expect(ProxyUrl.decode('/x/https/'), isNull);
    });
  });
}
