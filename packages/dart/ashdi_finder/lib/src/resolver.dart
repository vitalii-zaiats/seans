import 'models.dart';
import 'player.dart';

/// Fetches a player page and returns its body as text.
///
/// This package never makes a request itself. Hand it something that does, and
/// proxies, retries, timeouts and headers stay where they belong — in the
/// application. A test hands it a canned string.
///
/// The [referer] is what the player page expects to have been opened from;
/// ashdi serves a different page without it.
typedef AshdiFetcher = Future<String> Function(Uri url, {String? referer});

/// Raised when the player page could not be read or held no stream.
class AshdiException implements Exception {
  const AshdiException(this.message, {this.url, this.cause});

  final String message;
  final Uri? url;
  final Object? cause;

  @override
  String toString() =>
      'AshdiException: $message${url == null ? '' : ' ($url)'}';
}

/// Turns an ashdi player URL into the streams behind it.
class AshdiResolver {
  const AshdiResolver({required this.fetch, this.referer});

  /// How this resolver reaches the network.
  final AshdiFetcher fetch;

  /// Sent as the `Referer` for every player request. ashdi checks it.
  final String? referer;

  /// Opens [playerUrl] and reads its config.
  ///
  /// Throws [AshdiException] when the page cannot be fetched. A page that
  /// loads but holds nothing playable comes back as an [AshdiPlayer] with no
  /// streams, which is a different thing and worth telling apart.
  Future<AshdiPlayer> resolve(String playerUrl) async {
    final url = Uri.parse(playerUrl);

    final String html;
    try {
      html = await fetch(url, referer: referer);
    } on AshdiException {
      rethrow;
    } catch (error) {
      throw AshdiException(
        'could not open the player page',
        url: url,
        cause: error,
      );
    }

    return AshdiPlayer(
      url: playerUrl,
      streams: extractStreams(html),
      episodes: extractEpisodes(html),
    );
  }

  /// The single stream to play for [playerUrl].
  ///
  /// For a `/serial/` page that carries a playlist, [season] and [episode]
  /// pick a leaf; without them the first leaf wins. Returns `null` when the
  /// page held nothing playable.
  Future<AshdiStream?> resolveStream(
    String playerUrl, {
    int? season,
    int? episode,
  }) async {
    final player = await resolve(playerUrl);

    if (player.episodes.isEmpty || (season == null && episode == null)) {
      return player.streams.isEmpty ? null : player.streams.first;
    }

    for (final leaf in player.episodes) {
      final seasonMatches = season == null || leaf.season == season;
      final episodeMatches = episode == null || leaf.episode == episode;
      if (seasonMatches && episodeMatches && leaf.streams.isNotEmpty) {
        return leaf.streams.first;
      }
    }

    return player.streams.isEmpty ? null : player.streams.first;
  }
}
