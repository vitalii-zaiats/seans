import 'dart:io';

import 'package:hls/hls.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('a real master playlist', () {
    late HlsMaster master;

    setUp(() => master = parseMaster(fixture('master-sweet.m3u8')));

    test('finds every quality', () {
      expect(master.variants, hasLength(3));
      expect(master.variants.map((v) => v.height), [1080, 720, 480]);
    });

    test('reads a variant whole', () {
      final best = master.variants.first;

      expect(best.width, 1920);
      expect(best.height, 1080);
      expect(best.bandwidth, 5000000);
      expect(best.frameRate, 25);
      expect(best.codecs, 'avc1.42E01E,mp4a.40.2');
      expect(best.url, startsWith('https://'));
    });

    test('the comma inside CODECS does not split the attributes', () {
      expect(
        master.variants.first.codecs,
        contains(','),
        reason: 'splitting on every comma would cut this in half',
      );
      expect(master.variants.first.bandwidth, isNot(0));
    });

    test('labels read the way people say them', () {
      expect(master.variants.map((v) => v.label), ['1080p', '720p', '480p']);
    });
  });

  group('choosing for a screen', () {
    final master = parseMaster(fixture('master-sweet.m3u8'));

    test('a 720p panel gets 720p, not 1080p', () {
      expect(
        master.bestFor(720)?.height,
        720,
        reason: 'detail beyond the panel is decoded and then thrown away',
      );
    });

    test('a 4K panel gets the best there is', () {
      expect(master.bestFor(2160)?.height, 1080);
    });

    test('an odd small screen still gets something playable', () {
      expect(master.bestFor(240)?.height, 480);
    });

    test('nothing to choose from is null, not a crash', () {
      expect(const HlsMaster([]).bestFor(720), isNull);
    });
  });

  group('what it is not', () {
    test('a media playlist has no qualities to offer', () {
      final master = parseMaster(
        '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4.000\nseg-1.ts\n',
      );

      expect(master.isEmpty, isTrue);
    });

    test('and neither has an empty body', () {
      expect(parseMaster('').isEmpty, isTrue);
    });

    test('a stream line with no URL after it is skipped', () {
      final master = parseMaster(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x2\n',
      );

      expect(master.isEmpty, isTrue);
    });
  });

  group('addresses', () {
    test('a bare file name is resolved against the playlist', () {
      final master = parseMaster(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720\n'
        'v/720.m3u8\n',
        base: Uri.parse('https://cdn.test/a/master.m3u8'),
      );

      expect(master.variants.single.url, 'https://cdn.test/a/v/720.m3u8');
    });

    test('an absolute one is left alone', () {
      final master = parseMaster(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://other.test/x.m3u8\n',
        base: Uri.parse('https://cdn.test/a/master.m3u8'),
      );

      expect(master.variants.single.url, 'https://other.test/x.m3u8');
    });

    test('a comment between the tag and the URL is stepped over', () {
      final master = parseMaster(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720\n'
        '# a comment\nhttps://cdn.test/720.m3u8\n',
      );

      expect(master.variants.single.url, 'https://cdn.test/720.m3u8');
    });
  });

  test('a variant with no resolution falls back to its bitrate', () {
    final master = parseMaster(
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2500000\nhttps://cdn.test/a.m3u8\n',
    );

    expect(master.variants.single.label, '2.5 Мбіт');
    expect(master.variants.single.hasSize, isFalse);
  });
}
