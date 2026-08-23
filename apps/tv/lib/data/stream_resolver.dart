import 'dart:convert';

import 'package:ashdi_finder/ashdi_finder.dart';
import 'package:http/http.dart' as http;
import 'package:super_movies_api/super_movies_api.dart';

/// Turns a title's provider links into something ExoPlayer can open.
///
/// The catalogue hands out embed pages, not streams. Every provider it lists is
/// tried in turn until one yields an `.m3u8`, so a title whose first provider
/// has gone quiet still plays.
class StreamResolver {
  StreamResolver({http.Client? client, AshdiResolver? ashdi})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _ashdi =
          ashdi ??
          AshdiResolver(
            referer: _referer,
            fetch: (url, {referer}) async {
              final response = await (client ?? http.Client()).get(
                url,
                headers: {
                  // The embed page serves a different body — or none — to a
                  // request that does not look like the site's own iframe.
                  'Referer': ?referer,
                  'User-Agent': _userAgent,
                },
              );
              if (response.statusCode != 200) {
                throw AshdiException(
                  'player page answered ${response.statusCode}',
                  url: url,
                );
              }
              return utf8.decode(response.bodyBytes, allowMalformed: true);
            },
          );

  static const _referer = 'https://kinostrain.com/';

  /// What the player page and its playlists are asked with.
  ///
  /// Public because the playlist behind a resolved stream needs the same two
  /// headers, and ashdi answers 400 to a request carrying neither.
  static const userAgent = _userAgent;

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 12; BRAVIA) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  final http.Client _client;
  final bool _ownsClient;
  final AshdiResolver _ashdi;

  /// Every dub the site offers for [season] at [episode], in display order.
  ///
  /// Only ashdi's embed is understood, so a provider whose player this cannot
  /// read is left out rather than offered and then failing on selection.
  List<DubOption> options(Season season, {int? episode}) => [
    for (final provider in season.availablePlayers(episode: episode))
      for (final source in season.sourcesFor(provider, episode: episode))
        if (source.link.contains('ashdi.vip'))
          DubOption(provider: provider, source: source),
  ];

  /// Opens one particular dub, rather than whichever comes first.
  ///
  /// Throws [AshdiException] when the player page could not be read at all —
  /// which is a different thing from a page that loaded and held no stream,
  /// and the two want telling apart when a box says nothing works.
  Future<ResolvedStream?> resolveOption(
    DubOption option, {
    int? season,
    int? episode,
  }) async {
    final stream = await _ashdi.resolveStream(
      option.source.link,
      season: season,
      episode: episode,
    );
    if (stream == null) return null;
    return ResolvedStream(
      url: stream.url,
      provider: option.provider,
      dub: option.source.name,
      embedUrl: option.source.link,
    );
  }

  /// The stream for [season], optionally at [episode].
  ///
  /// Returns `null` when no provider gave one up — the caller shows the
  /// fallback rather than an error, because "nothing playable" is an ordinary
  /// state for a title the site has listed but not filled in.
  Future<ResolvedStream?> resolve(Season season, {int? episode}) async {
    for (final provider in season.availablePlayers(episode: episode)) {
      for (final source in season.sourcesFor(provider, episode: episode)) {
        // Only ashdi's player is understood. Another provider's embed is a
        // different page with a different config, and guessing at it would
        // fail in a way that looks like a broken title.
        if (!source.link.contains('ashdi.vip')) continue;

        try {
          final stream = await _ashdi.resolveStream(
            source.link,
            season: season.isEpisodic ? null : season.number,
            episode: season.isEpisodic ? null : episode,
          );
          if (stream != null) {
            return ResolvedStream(
              url: stream.url,
              provider: provider,
              dub: source.name,
              embedUrl: source.link,
            );
          }
        } on AshdiException {
          // This dub is unreachable; the next one may not be.
          continue;
        }
      }
    }
    return null;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// One selectable voice-over, before it has been resolved to a stream.
class DubOption {
  const DubOption({required this.provider, required this.source});

  final String provider;
  final PlayerSource source;

  /// What to call it in the picker. Some entries carry no name at all.
  String get label => source.name.isEmpty ? provider : source.name;

  @override
  bool operator ==(Object other) =>
      other is DubOption &&
      other.provider == provider &&
      other.source.link == source.link;

  @override
  int get hashCode => Object.hash(provider, source.link);
}

/// A stream, and where it came from.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.provider,
    required this.dub,
    required this.embedUrl,
  });

  /// The `.m3u8` ExoPlayer opens.
  final String url;

  /// Provider key, e.g. `ashdi`.
  final String provider;

  /// The dub or release group this stream carries.
  final String dub;

  /// The page it was read out of — what to fall back to in a browser.
  final String embedUrl;
}
