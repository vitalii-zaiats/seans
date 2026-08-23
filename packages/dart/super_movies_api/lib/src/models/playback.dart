import '../json.dart';

/// One playable address read off a player page.
///
/// A page carries several — qualities, sometimes voices — and which of them to
/// open is the caller's business. The first is the one to play when nobody has
/// an opinion.
final class PlaybackStream {
  const PlaybackStream({
    required this.url,
    this.label,
    this.source = 'playerjs',
  });

  factory PlaybackStream.fromJson(JsonMap json) {
    const owner = 'PlaybackStream';
    return PlaybackStream(
      url: json.requireString('url', owner: owner),
      label: json.stringOrNull('label'),
      source: json.stringOrNull('source') ?? 'playerjs',
    );
  }

  /// The `.m3u8` itself, as the player page named it.
  final String url;

  /// The page's own words: a quality tag, a voice, or the whole playlist path.
  final String? label;

  /// `playerjs` when read from the page's configuration, `page-scan` when the
  /// page was swept for URLs instead — a guess, and worth knowing as one.
  final String source;
}
