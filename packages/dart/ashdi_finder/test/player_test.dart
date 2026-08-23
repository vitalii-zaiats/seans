import 'dart:convert';
import 'dart:io';

import 'package:ashdi_finder/ashdi_finder.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Wraps a Playerjs config the way a real page carries it.
String page(String fileValue, {String? subtitle}) =>
    '''
<html><body><div id="videoplayer1"></div><script>
  player = new Playerjs({
    id:"videoplayer1",
    file:'$fileValue',
    poster:"https://ashdi.vip/screen.jpg"${subtitle == null ? '' : ",\n    subtitle:'$subtitle'"}
  });
</script></body></html>
''';

void main() {
  group('films', () {
    test('reads the single stream off a captured player page', () {
      final streams = extractStreams(fixture('vod_film.html'));

      expect(streams, hasLength(1));
      expect(streams.single.url, endsWith('/index.m3u8'));
      expect(streams.single.url, startsWith('https://ashdi.vip/'));
      expect(streams.single.source, 'playerjs');
      expect(
        extractEpisodes(fixture('vod_film.html')),
        isEmpty,
        reason: 'a /vod/ page has no playlist',
      );
    });

    test('splits a multi-quality file into one stream per label', () {
      final streams = extractStreams(
        page('[720p]https://a.test/720.m3u8,[1080p]https://a.test/1080.m3u8'),
      );

      expect(streams.map((s) => s.label), ['720p', '1080p']);
      expect(streams.map((s) => s.url), [
        'https://a.test/720.m3u8',
        'https://a.test/1080.m3u8',
      ]);
    });

    test('ignores entries that are not m3u8', () {
      final streams = extractStreams(
        page('[720p]https://a.test/720.mp4,[1080p]https://a.test/1080.m3u8'),
      );

      expect(streams, hasLength(1));
      expect(streams.single.label, '1080p');
    });

    test('undoes JS escaping in the config value', () {
      final streams = extractStreams(page(r'https:\/\/a.test\/с\/index.m3u8'));

      expect(streams.single.url, 'https://a.test/с/index.m3u8');
    });

    test('sweeps the page when there is no Playerjs config', () {
      const html = '''
        <html><body>
          <script>var src = "https://a.test/one/index.m3u8";</script>
          <script>var alt = "https://a.test/two/index.m3u8";</script>
        </body></html>
      ''';

      final streams = extractStreams(html);

      expect(streams, hasLength(2));
      expect(streams.every((s) => s.source == 'page-scan'), isTrue);
    });

    test('reports the same URL once', () {
      const html = '''
        <script>a="https://a.test/x/index.m3u8";b="https://a.test/x/index.m3u8";</script>
      ''';

      expect(extractStreams(html), hasLength(1));
    });

    test('a page with nothing playable yields nothing', () {
      expect(extractStreams('<html><body>gone</body></html>'), isEmpty);
    });
  });

  group('serials', () {
    /// dub → season → episode, the shape a /serial/ page normally carries.
    String serialPage() {
      final playlist = jsonEncode([
        {
          'title': 'Postmodern',
          'folder': [
            {
              'title': 'Сезон 1',
              'folder': [
                {
                  'title': 'Серія 1',
                  'file': 'https://a.test/s01e01/index.m3u8',
                  'id': '268988',
                  'poster': 'https://a.test/s01e01.jpg',
                  'subtitle': '[Українські]https://a.test/s01e01_ua.vtt',
                },
                {
                  'title': 'Серія 2',
                  'file': 'https://a.test/s01e02/index.m3u8',
                },
              ],
            },
            {
              'title': 'Сезон 2',
              'folder': [
                {
                  'title': 'Серія 1',
                  'file': 'https://a.test/s02e01/index.m3u8',
                },
              ],
            },
          ],
        },
      ]);
      return page(playlist.replaceAll("'", r"\'"));
    }

    test('walks the playlist into episodes', () {
      final episodes = extractEpisodes(serialPage());

      expect(episodes, hasLength(3));
      expect(episodes.map((e) => (e.season, e.episode)), [
        (1, 1),
        (1, 2),
        (2, 1),
      ]);
      expect(episodes.every((e) => e.dub == 'Postmodern'), isTrue);
    });

    test('keeps the folder path as the stream label', () {
      final first = extractEpisodes(serialPage()).first;

      expect(first.streams.single.label, 'Postmodern / Сезон 1 / Серія 1');
      expect(first.folders, ['Postmodern', 'Сезон 1']);
    });

    test('carries poster, id and subtitles off the leaf', () {
      final first = extractEpisodes(serialPage()).first;

      expect(first.videoId, '268988');
      expect(first.poster, 'https://a.test/s01e01.jpg');
      expect(first.subtitles.single.label, 'Українські');
      expect(first.subtitles.single.url, endsWith('_ua.vtt'));
    });

    test('flattens every episode stream into the page total', () {
      final streams = extractStreams(serialPage());

      expect(streams, hasLength(3));
    });

    test('a single-dub serial that drops the outer folder still parses', () {
      final playlist = jsonEncode([
        {
          'title': 'Сезон 3',
          'folder': [
            {'title': 'Серія 7', 'file': 'https://a.test/x/index.m3u8'},
          ],
        },
      ]);

      final episode = extractEpisodes(page(playlist)).single;

      expect(episode.season, 3);
      expect(episode.episode, 7);
      expect(episode.dub, isNull);
    });

    test('falls back to the file name when titles carry no numbers', () {
      final playlist = jsonEncode([
        {
          'title': 'Дубляж',
          'folder': [
            {
              'title': 'Перша',
              'file': 'https://a.test/show.s02e05.1080p_1/index.m3u8',
            },
          ],
        },
      ]);

      final episode = extractEpisodes(page(playlist)).single;

      expect(episode.season, 2);
      expect(episode.episode, 5);
      expect(episode.dub, 'Дубляж');
    });

    test('reads a pair aired as one file', () {
      final playlist = jsonEncode([
        {
          'title': 'Сезон 1',
          'folder': [
            {'title': 'Серія 12-13', 'file': 'https://a.test/x/index.m3u8'},
          ],
        },
      ]);

      final episode = extractEpisodes(page(playlist)).single;

      expect(episode.episode, 12);
      expect(episode.episodeEnd, 13);
    });

    test('matches season and episode words regardless of case', () {
      final playlist = jsonEncode([
        {
          'title': 'СЕЗОН 4',
          'folder': [
            {'title': 'ЕПІЗОД 9', 'file': 'https://a.test/x/index.m3u8'},
          ],
        },
      ]);

      final episode = extractEpisodes(page(playlist)).single;

      expect(episode.season, 4);
      expect(episode.episode, 9);
    });

    test('a title with no numbers anywhere stays honest about it', () {
      final playlist = jsonEncode([
        {
          'title': 'Бонус',
          'folder': [
            {'title': 'За кадром', 'file': 'https://a.test/extra/index.m3u8'},
          ],
        },
      ]);

      final episode = extractEpisodes(page(playlist)).single;

      expect(episode.season, isNull);
      expect(episode.episode, isNull);
      expect(episode.url, 'https://a.test/extra/index.m3u8');
    });
  });

  group('AshdiResolver', () {
    test('passes the referer through to the fetcher', () async {
      Uri? seen;
      String? seenReferer;
      final resolver = AshdiResolver(
        referer: 'https://kinostrain.com/',
        fetch: (url, {referer}) async {
          seen = url;
          seenReferer = referer;
          return fixture('vod_film.html');
        },
      );

      await resolver.resolve('https://ashdi.vip/vod/276636');

      expect(seen.toString(), 'https://ashdi.vip/vod/276636');
      expect(seenReferer, 'https://kinostrain.com/');
    });

    test('wraps a fetch failure', () async {
      final resolver = AshdiResolver(
        fetch: (url, {referer}) async => throw const SocketFailure(),
      );

      await expectLater(
        resolver.resolve('https://ashdi.vip/vod/1'),
        throwsA(
          isA<AshdiException>().having(
            (e) => e.cause,
            'cause',
            isA<SocketFailure>(),
          ),
        ),
      );
    });

    test('a page that loads but holds nothing is not an error', () async {
      final resolver = AshdiResolver(
        fetch: (url, {referer}) async => '<html>nothing</html>',
      );

      final player = await resolver.resolve('https://ashdi.vip/vod/1');

      expect(player.streams, isEmpty);
      expect(player.firstUrl, isNull);
      expect(player.isSerial, isFalse);
    });

    test('resolveStream picks the asked-for episode', () async {
      final playlist = jsonEncode([
        {
          'title': 'Сезон 2',
          'folder': [
            {'title': 'Серія 1', 'file': 'https://a.test/s02e01/index.m3u8'},
            {'title': 'Серія 2', 'file': 'https://a.test/s02e02/index.m3u8'},
          ],
        },
      ]);
      final resolver = AshdiResolver(
        fetch: (url, {referer}) async => page(playlist),
      );

      final stream = await resolver.resolveStream(
        'https://ashdi.vip/serial/1',
        season: 2,
        episode: 2,
      );

      expect(stream?.url, 'https://a.test/s02e02/index.m3u8');
    });

    test(
      'resolveStream falls back to the first leaf for an unknown episode',
      () async {
        final playlist = jsonEncode([
          {
            'title': 'Сезон 1',
            'folder': [
              {'title': 'Серія 1', 'file': 'https://a.test/one/index.m3u8'},
            ],
          },
        ]);
        final resolver = AshdiResolver(
          fetch: (url, {referer}) async => page(playlist),
        );

        final stream = await resolver.resolveStream(
          'https://ashdi.vip/serial/1',
          episode: 99,
        );

        expect(stream?.url, 'https://a.test/one/index.m3u8');
      },
    );

    test('resolveStream on a film ignores episode hints', () async {
      final resolver = AshdiResolver(
        fetch: (url, {referer}) async => fixture('vod_film.html'),
      );

      final stream = await resolver.resolveStream(
        'https://ashdi.vip/vod/1',
        episode: 3,
      );

      expect(stream?.url, endsWith('/index.m3u8'));
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
