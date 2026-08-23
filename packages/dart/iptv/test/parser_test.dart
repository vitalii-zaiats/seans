import 'dart:io';

import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('a captured playlist', () {
    test('reads the channels out of a real list', () {
      final playlist = parsePlaylist(fixture('ukraine_head.m3u8'));

      expect(playlist.channels, isNotEmpty);
      final first = playlist.channels.first;
      expect(first.name, isNotEmpty);
      expect(first.url, contains('m3u8'));
      expect(first.tvgId, isNotNull);
      expect(first.group, isNotNull);
    });

    test('picks up the programme-guide urls off the header', () {
      final playlist = parsePlaylist(fixture('ukraine_head.m3u8'));

      // The header lists many, comma separated.
      expect(playlist.epgUrls, isNotEmpty);
      expect(playlist.epgUrls.first, startsWith('http'));
    });
  });

  group('the shapes a playlist arrives in', () {
    test('parses the plain pair', () {
      const text = '''
#EXTM3U
#EXTINF:-1 tvg-id="a.ua" tvg-logo="https://x.test/a.png" group-title="Новини",Перший
https://x.test/a/index.m3u8
''';

      final channel = parsePlaylist(text).channels.single;

      expect(channel.name, 'Перший');
      expect(channel.url, 'https://x.test/a/index.m3u8');
      expect(channel.tvgId, 'a.ua');
      expect(channel.logoUrl, 'https://x.test/a.png');
      expect(channel.group, 'Новини');
    });

    test('a comma inside an attribute does not cut the name off', () {
      // The classic way a naive split on ',' mangles a list.
      const text = '''
#EXTM3U
#EXTINF:-1 group-title="Новини, спорт",Канал
https://x.test/a.m3u8
''';

      final channel = parsePlaylist(text).channels.single;

      expect(channel.group, 'Новини, спорт');
      expect(channel.name, 'Канал');
    });

    test('single quotes work as well as double', () {
      const text = "#EXTINF:-1 tvg-id='b.ua',Другий\nhttps://x.test/b.m3u8";

      expect(parsePlaylist(text).channels.single.tvgId, 'b.ua');
    });

    test('CRLF endings are not part of the URL', () {
      const text =
          '#EXTM3U\r\n#EXTINF:-1,Канал\r\nhttps://x.test/a.m3u8\r\n';

      expect(parsePlaylist(text).channels.single.url, 'https://x.test/a.m3u8');
    });

    test('directives between the pair are stepped over', () {
      const text = '''
#EXTINF:-1,Канал
#EXTVLCOPT:http-user-agent=Mozilla
#EXTVLCOPT:http-referrer=https://x.test/
https://x.test/a.m3u8
''';

      final channel = parsePlaylist(text).channels.single;

      expect(channel.url, 'https://x.test/a.m3u8');
      expect(channel.name, 'Канал');
    });

    test('#EXTGRP stands in for a missing group-title', () {
      const text = '#EXTINF:-1,Канал\n#EXTGRP:Спорт\nhttps://x.test/a.m3u8';

      expect(parsePlaylist(text).channels.single.group, 'Спорт');
    });

    test('group-title wins over #EXTGRP when both are there', () {
      const text =
          '#EXTINF:-1 group-title="Кіно",Канал\n#EXTGRP:Спорт\nhttps://x.test/a.m3u8';

      expect(parsePlaylist(text).channels.single.group, 'Кіно');
    });

    test('falls back to tvg-name when the display name is missing', () {
      const text = '#EXTINF:-1 tvg-name="Резервна",\nhttps://x.test/a.m3u8';

      expect(parsePlaylist(text).channels.single.name, 'Резервна');
    });

    test('reads the channel number', () {
      const text = '#EXTINF:-1 tvg-chno="12",Канал\nhttps://x.test/a.m3u8';

      expect(parsePlaylist(text).channels.single.number, 12);
    });
  });

  group('what it refuses to guess', () {
    test('an entry with no URL is dropped, not attached to the next', () {
      const text = '''
#EXTINF:-1,Осиротілий
#EXTINF:-1,Справжній
https://x.test/real.m3u8
''';

      final channels = parsePlaylist(text).channels;

      expect(channels, hasLength(1));
      expect(channels.single.name, 'Справжній');
    });

    test('a URL with no #EXTINF above it is ignored', () {
      const text = '#EXTM3U\nhttps://x.test/orphan.m3u8';

      expect(parsePlaylist(text).channels, isEmpty);
    });

    test('an empty playlist is empty, not an error', () {
      expect(parsePlaylist('').isEmpty, isTrue);
      expect(parsePlaylist('#EXTM3U').isEmpty, isTrue);
    });

    test('one bad entry does not cost the rest', () {
      const text = '''
#EXTM3U
#EXTINF:-1,Перший
https://x.test/a.m3u8
#EXTINF this line has no comma at all
https://x.test/b.m3u8
#EXTINF:-1,Третій
https://x.test/c.m3u8
''';

      expect(
        parsePlaylist(text).channels.map((c) => c.name),
        ['Перший', 'Третій'],
      );
    });
  });

  group('channels', () {
    IptvChannel at(String url) => IptvChannel(name: 'X', url: url);

    test('knows an HLS stream from anything else', () {
      expect(at('https://x.test/a/index.m3u8').isHls, isTrue);
      expect(at('https://x.test/a.mp4').isHls, isFalse);
    });

    test('flags plain HTTP, which Android blocks by default', () {
      expect(at('http://x.test/a.m3u8').isCleartext, isTrue);
      expect(at('https://x.test/a.m3u8').isCleartext, isFalse);
    });
  });

  group('grouping', () {
    test('keeps the order the playlist listed the groups in', () {
      const text = '''
#EXTINF:-1 group-title="Новини",A
https://x.test/a.m3u8
#EXTINF:-1 group-title="Спорт",B
https://x.test/b.m3u8
#EXTINF:-1 group-title="Новини",C
https://x.test/c.m3u8
''';

      final playlist = parsePlaylist(text);

      expect(playlist.groups, ['Новини', 'Спорт']);
      expect(
        groupChannels(playlist.channels)['Новини']!.map((c) => c.name),
        ['A', 'C'],
      );
    });

    test('an ungrouped channel lands somewhere rather than vanishing', () {
      const text = '#EXTINF:-1,Сам по собі\nhttps://x.test/a.m3u8';

      expect(groupChannels(parsePlaylist(text).channels).keys, ['Інше']);
    });
  });

  group('IptvLoader', () {
    test('parses what the fetcher hands back', () async {
      final loader = IptvLoader(
        fetch: (url) async => fixture('ukraine_head.m3u8'),
      );

      final playlist = await loader.load(IptvSource.freeTvUkraine);

      expect(playlist.channels, isNotEmpty);
    });

    test('asks for the source url', () async {
      Uri? seen;
      final loader = IptvLoader(
        fetch: (url) async {
          seen = url;
          return '#EXTM3U';
        },
      );

      await loader.load(IptvSource.freeTvUkraine);

      expect(seen.toString(), IptvSource.freeTvUkraine.url);
      expect(seen!.host, 'raw.githubusercontent.com');
    });

    test('wraps a fetch failure', () async {
      final loader = IptvLoader(
        fetch: (url) async => throw const SocketFailure(),
      );

      await expectLater(
        loader.load(IptvSource.freeTvUkraine),
        throwsA(
          isA<IptvException>()
              .having((e) => e.cause, 'cause', isA<SocketFailure>()),
        ),
      );
    });

    test('a list that loads but holds nothing is not a failure', () async {
      final loader = IptvLoader(fetch: (url) async => '#EXTM3U');

      expect((await loader.load(IptvSource.freeTvUkraine)).isEmpty, isTrue);
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
