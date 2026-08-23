import 'package:cors_proxy/cors_proxy.dart';
import 'package:test/test.dart';

void main() {
  group('recognising one', () {
    test('by what it says it is', () {
      expect(
        looksLikePlaylist(
          contentType: 'application/vnd.apple.mpegurl',
          path: '/stream',
        ),
        isTrue,
      );
      expect(
        looksLikePlaylist(contentType: 'audio/mpegurl', path: '/stream'),
        isTrue,
      );
    });

    test('by its name, when it says nothing useful', () {
      expect(
        looksLikePlaylist(
          contentType: 'application/octet-stream',
          path: '/hls/index.m3u8',
        ),
        isTrue,
      );
    });

    test('and leaving a segment alone', () {
      // The segments are the bulk of a stream and must not be buffered.
      expect(
        looksLikePlaylist(contentType: 'video/mp2t', path: '/hls/seg-1.ts'),
        isFalse,
      );
    });
  });

  group('rewriting', () {
    test('an absolute variant is pointed back at the proxy', () {
      // What ashdi actually sends: the master playlist names each quality in
      // full, and a player following that leaves the origin.
      const master =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:RESOLUTION=1920x800,BANDWIDTH=2128000\n'
          'https://ashdi.vip/video21/hls/1080/abc/index.m3u8\n';

      expect(
        rewritePlaylist(master),
        contains('/x/https/ashdi.vip/video21/hls/1080/abc/index.m3u8'),
      );
    });

    test('a relative one is left exactly as it was', () {
      // It already resolves correctly against the proxied address, and
      // touching it would only be a chance to get it wrong.
      const media = '#EXTM3U\n#EXTINF:6.0,\nseg-1.ts\n#EXTINF:6.0,\nseg-2.ts\n';

      expect(rewritePlaylist(media), media);
    });

    test('the tags themselves are untouched', () {
      const media = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-ENDLIST\n';

      expect(rewritePlaylist(media), media);
    });

    test('a key named inside a tag is rewritten too', () {
      // An encrypted stream that cannot reach its key plays nothing, and the
      // key is not on a line of its own.
      const media =
          '#EXT-X-KEY:METHOD=AES-128,URI="https://ashdi.vip/key/abc",IV=0x1\n';

      final out = rewritePlaylist(media);
      expect(out, contains('URI="/x/https/ashdi.vip/key/abc"'));
      expect(out, contains('METHOD=AES-128'));
      expect(out, contains('IV=0x1'));
    });

    test('and so is an initialisation segment', () {
      const media = '#EXT-X-MAP:URI="https://host/init.mp4"\n';

      expect(rewritePlaylist(media), contains('URI="/x/https/host/init.mp4"'));
    });

    test('a relative key is left alone as well', () {
      const media = '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n';

      expect(rewritePlaylist(media), media);
    });

    test('a base goes in front of every rewritten address', () {
      const master = '#EXTM3U\nhttps://host/a.m3u8\n';

      expect(
        rewritePlaylist(master, base: 'http://box.local:8080'),
        contains('http://box.local:8080/x/https/host/a.m3u8'),
      );
    });

    test('line endings survive, because a player is strict about them', () {
      const media = '#EXTM3U\r\n#EXTINF:6.0,\r\nseg-1.ts\r\n';

      expect(rewritePlaylist(media), media);
    });

    test('an empty playlist stays empty rather than throwing', () {
      expect(rewritePlaylist(''), '');
    });
  });
}
