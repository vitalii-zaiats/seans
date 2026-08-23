import 'channel.dart';
import 'parser.dart';

/// Fetches a playlist and returns its body as text.
///
/// This package makes no requests of its own. Hand it something that does, and
/// timeouts, headers and caching stay in the application where they belong; a
/// test hands it a canned string.
typedef PlaylistFetcher = Future<String> Function(Uri url);

/// Raised when a playlist could not be read.
class IptvException implements Exception {
  const IptvException(this.message, {this.url, this.cause});

  final String message;
  final Uri? url;
  final Object? cause;

  @override
  String toString() => 'IptvException: $message${url == null ? '' : ' ($url)'}';
}

/// A named playlist somebody can subscribe to.
class IptvSource {
  const IptvSource({required this.id, required this.title, required this.url});

  final String id;
  final String title;
  final String url;

  /// The Ukrainian list from the Free-TV index.
  ///
  /// Fetched at run time rather than baked into the app: the list is edited
  /// often — dead channels are pulled, URLs move — and a copy shipped inside an
  /// APK is wrong the week after it is built. It is also somebody else's
  /// dataset, and pointing at it is not the same as republishing it.
  static const freeTvUkraine = IptvSource(
    id: 'free-tv-ua',
    title: 'Free-TV · Україна',
    url:
        'https://raw.githubusercontent.com/Free-TV/IPTV/master'
        '/playlists/playlist_ukraine.m3u8',
  );

  static const defaults = <IptvSource>[freeTvUkraine];
}

/// Loads playlists through an injected fetcher.
class IptvLoader {
  const IptvLoader({required this.fetch});

  final PlaylistFetcher fetch;

  /// Reads [source] and parses it.
  ///
  /// Throws [IptvException] when the playlist could not be fetched. One that
  /// loads and holds nothing comes back as an empty playlist, which is a
  /// different thing and worth telling apart.
  Future<IptvPlaylist> load(IptvSource source) async {
    final url = Uri.parse(source.url);

    final String body;
    try {
      body = await fetch(url);
    } on IptvException {
      rethrow;
    } catch (error) {
      throw IptvException(
        'не вдалося завантажити список',
        url: url,
        cause: error,
      );
    }

    return parsePlaylist(body);
  }
}

/// Groups channels the way a screen wants them: by `group-title`, in the order
/// the playlist listed them.
Map<String, List<IptvChannel>> groupChannels(List<IptvChannel> channels) {
  final grouped = <String, List<IptvChannel>>{};
  for (final channel in channels) {
    final group = channel.group ?? 'Інше';
    grouped.putIfAbsent(group, () => []).add(channel);
  }
  return grouped;
}
