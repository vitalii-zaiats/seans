/// Reads an M3U playlist into channels.
///
/// The format is a header line, then pairs: an `#EXTINF` line carrying the
/// attributes and the display name, and the URL under it.
///
/// ```
/// #EXTM3U
/// #EXTINF:-1 tvg-id="Pershyi.ua" tvg-logo="…" group-title="Ukraine",Pershyi
/// https://example.test/stream.m3u8
/// ```
///
/// In practice the pairs are not always adjacent: players write `#EXTVLCOPT`
/// and `#EXTGRP` lines between them, files arrive with CRLF endings, and an
/// entry whose URL never appears has to be dropped rather than silently
/// attached to the next one.
library;

import 'channel.dart';

/// `attr="value"`, tolerating single quotes and spaces inside the value.
final RegExp _attribute = RegExp(
  '''([A-Za-z0-9_-]+)\\s*=\\s*(?:"([^"]*)"|'([^']*)')''',
);

/// Everything a playlist can hold that this parser understands.
class IptvPlaylist {
  const IptvPlaylist({required this.channels, this.epgUrls = const []});

  final List<IptvChannel> channels;

  /// `x-tvg-url` off the header — programme guides, for when that is built.
  final List<String> epgUrls;

  bool get isEmpty => channels.isEmpty;

  /// Every distinct `group-title`, in the order they first appear.
  List<String> get groups {
    final seen = <String>[];
    for (final channel in channels) {
      final group = channel.group;
      if (group != null && group.isNotEmpty && !seen.contains(group)) {
        seen.add(group);
      }
    }
    return seen;
  }
}

/// Parses [text] as an M3U playlist.
///
/// Never throws: a malformed line is skipped, because a list of two hundred
/// channels with one bad entry should still give back a hundred and
/// ninety-nine.
IptvPlaylist parsePlaylist(String text) {
  final channels = <IptvChannel>[];
  final epgUrls = <String>[];

  String? pendingInfo;
  String? pendingGroup;

  for (final raw in text.split('\n')) {
    // Files come with CRLF as often as not.
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTM3U')) {
      epgUrls.addAll(_epgUrls(line));
      continue;
    }

    if (line.startsWith('#EXTINF')) {
      pendingInfo = line;
      pendingGroup = null;
      continue;
    }

    // Written by some exporters instead of a `group-title` attribute.
    if (line.startsWith('#EXTGRP:')) {
      pendingGroup = line.substring('#EXTGRP:'.length).trim();
      continue;
    }

    // Anything else beginning with # is a directive this does not read —
    // `#EXTVLCOPT`, comments — and must not be mistaken for a URL.
    if (line.startsWith('#')) continue;

    if (pendingInfo == null) continue;

    final channel = _channel(pendingInfo, line, pendingGroup);
    if (channel != null) channels.add(channel);
    pendingInfo = null;
    pendingGroup = null;
  }

  return IptvPlaylist(channels: channels, epgUrls: epgUrls);
}

IptvChannel? _channel(String info, String url, String? fallbackGroup) {
  // `#EXTINF:-1 attrs,Display Name` — the name is after the *last* comma that
  // is not inside a quoted attribute, which in practice is the first comma
  // after the closing quote of the final attribute.
  final comma = _nameComma(info);
  if (comma < 0) return null;

  final name = info.substring(comma + 1).trim();
  final attributes = _attributes(info.substring(0, comma));

  final display = name.isNotEmpty
      ? name
      : (attributes['tvg-name'] ?? '').trim();
  if (display.isEmpty) return null;

  return IptvChannel(
    name: display,
    url: url,
    logoUrl: _clean(attributes['tvg-logo']),
    tvgId: _clean(attributes['tvg-id']),
    group: _clean(attributes['group-title']) ?? _clean(fallbackGroup),
    number: int.tryParse(attributes['tvg-chno'] ?? ''),
    country: _clean(attributes['tvg-country']),
  );
}

/// The comma that separates the attributes from the display name.
///
/// Scanned rather than found with `indexOf`, because a value like
/// `group-title="News, Sport"` contains one and would cut the line in half.
int _nameComma(String info) {
  var inQuote = false;
  String? quote;

  for (var i = 0; i < info.length; i++) {
    final char = info[i];
    if (char == '"' || char == "'") {
      if (!inQuote) {
        inQuote = true;
        quote = char;
      } else if (char == quote) {
        inQuote = false;
        quote = null;
      }
      continue;
    }
    if (char == ',' && !inQuote) return i;
  }
  return -1;
}

Map<String, String> _attributes(String source) {
  final attributes = <String, String>{};
  for (final match in _attribute.allMatches(source)) {
    final value = match[2] ?? match[3];
    if (value != null) attributes[match[1]!.toLowerCase()] = value;
  }
  return attributes;
}

List<String> _epgUrls(String header) {
  final url = _attributes(header)['x-tvg-url'];
  if (url == null) return const [];
  return [
    for (final part in url.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
