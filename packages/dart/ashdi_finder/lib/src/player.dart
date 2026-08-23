/// Pulls `.m3u8` stream URLs out of an ashdi.vip player page.
///
/// The page hands its config to Playerjs:
///
/// ```js
/// player = new Playerjs({ id:"videoplayer167527", file:'https://.../index.m3u8', ... })
/// ```
///
/// `file` is either a single URL, a comma-separated multi-quality list
/// (`[720p]url,[1080p]url`), or — on a `/serial/` page — a JSON playlist nested
/// dub → season → episode:
///
/// ```json
/// [{"title":"Postmodern","folder":[
///     {"title":"Сезон 1","folder":[
///         {"title":"Серія 1","file":"https://.../index.m3u8","id":"268988"}, ...
/// ```
///
/// That nesting is a habit rather than a contract — a serial with one dub drops
/// the outer folder, a mini-series has no seasons — so the walk keeps every
/// folder title it passed and reads the numbers off the titles instead of off
/// the depth.
library;

import 'dart:convert';

import 'models.dart';

final RegExp _m3u8 = RegExp(r"""https?://[^\s'"\\<>()]+\.m3u8[^\s'"\\<>()]*""");

final RegExp _playerjsFile = RegExp(
  r"""new\s+Playerjs\s*\(\s*\{[\s\S]*?\bfile\s*:\s*(['"])([\s\S]*?)(?<!\\)\1""",
);

final RegExp _quality = RegExp(r'\[([^\]]+)\]\s*([^,]+)');

final RegExp _escape = RegExp(r'\\u([0-9a-fA-F]{4})|\\([\s\S])');

final RegExp _season = RegExp(
  r'сезон\s*(\d+)|(\d+)\s*(?:-й\s*)?сезон',
  caseSensitive: false,
  unicode: true,
);

final RegExp _episodeNumbers = RegExp(
  r'(?:сер[ії]я|епізод)\s*(\d+)(?:\s*[-–—]\s*(\d+))?|(\d+)\s*(?:сер[ії]я|епізод)',
  caseSensitive: false,
  unicode: true,
);

/// The last resort when a title carries no numbers:
/// `.../foo.s01e02.1080p_268989/...`
final RegExp _fileName = RegExp(
  r'[._/-]s(\d{1,2})e(\d{1,3})',
  caseSensitive: false,
);

const Map<String, String> _shortEscapes = {
  'n': '\n',
  't': '\t',
  'r': '\r',
  'b': '\b',
  'f': '\f',
};

/// Every `.m3u8` stream on a player page, in document order, deduplicated.
List<AshdiStream> extractStreams(String html) {
  final config = _playerjsConfig(html);
  var streams = config == null ? const <AshdiStream>[] : _configStreams(config);

  if (streams.isEmpty) {
    // Nothing structured? Sweep the whole page for m3u8 URLs.
    streams = [
      for (final match in _m3u8.allMatches(html))
        AshdiStream(url: match[0]!, source: 'page-scan'),
    ];
  }

  return _dedupe(streams);
}

/// Every episode a serial player lists, in playlist order.
///
/// Empty for a film — a `/vod/` page plays one file and has no playlist to
/// walk.
List<AshdiEpisode> extractEpisodes(String html) {
  final config = _playerjsConfig(html);
  return config == null ? const [] : _playlist(config);
}

/// A film's own `file` value, or every stream the episodes add up to.
List<AshdiStream> _configStreams(String config) {
  final episodes = _playlist(config);
  if (episodes.isNotEmpty) {
    return [for (final episode in episodes) ...episode.streams];
  }
  return _files(config, null);
}

String? _playerjsConfig(String html) {
  final match = _playerjsFile.firstMatch(html);
  return match == null ? null : _unescape(match[2]!);
}

/// Undoes JS string escaping (`\/`, `\"`, `\u0421`) without touching UTF-8 text.
String _unescape(String value) => value.replaceAllMapped(_escape, (match) {
  final code = match[1];
  if (code != null) return String.fromCharCode(int.parse(code, radix: 16));
  final char = match[2]!;
  return _shortEscapes[char] ?? char;
});

/// The playlist a serial's `file` holds. Empty when it is a plain URL list.
List<AshdiEpisode> _playlist(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('[{') && !trimmed.startsWith('{')) return const [];

  try {
    return _walk(jsonDecode(trimmed), const []);
  } on FormatException {
    return const []; // not a playlist after all — read it as URLs
  }
}

/// Recurses a Playerjs playlist, remembering the folders a leaf sits under.
List<AshdiEpisode> _walk(Object? node, List<String> folders) {
  if (node is List) {
    return [for (final item in node) ..._walk(item, folders)];
  }
  if (node is! Map) return const [];

  final raw = node['title'] ?? node['comment'];
  final title = raw is String ? raw.trim() : '';

  final folder = node['folder'];
  if (folder is List) {
    return _walk(folder, [...folders, if (title.isNotEmpty) title]);
  }

  final file = node['file'];
  if (file is! String) return const [];

  return [_episode(node, title, folders, file)];
}

AshdiEpisode _episode(
  Map<Object?, Object?> node,
  String title,
  List<String> folders,
  String file,
) {
  final (season, dub) = _seasonAndDub(folders);
  final (episode, episodeEnd) = _episodeNumbersOf(title);

  var resolvedSeason = season;
  var resolvedEpisode = episode;
  if (resolvedSeason == null || resolvedEpisode == null) {
    // Titles are the uploader's words; the file name is the fallback that does
    // not depend on them.
    final fromName = _fileName.firstMatch(file);
    if (fromName != null) {
      resolvedSeason ??= int.parse(fromName[1]!);
      resolvedEpisode ??= int.parse(fromName[2]!);
    }
  }

  return AshdiEpisode(
    title: title,
    season: resolvedSeason,
    episode: resolvedEpisode,
    episodeEnd: episodeEnd,
    dub: dub,
    // The label stays the whole path — "Postmodern / Сезон 1 / Серія 1" — so a
    // flattened stream still says where it came from.
    streams: _files(file, _join([...folders, title])),
    subtitles: _subtitles(node['subtitle']),
    poster: _text(node['poster']),
    videoId: _text(node['id']) ?? _text(node['vid']),
    folders: folders,
  );
}

/// Which folder was the season, and which one named the voices.
(int?, String?) _seasonAndDub(List<String> folders) {
  int? season;
  String? dub;

  for (final folder in folders) {
    final number = _seasonNumber(folder);
    if (number != null) {
      season = number;
    } else {
      dub ??= folder;
    }
  }

  return (season, dub);
}

int? _seasonNumber(String title) {
  final match = _season.firstMatch(title);
  if (match == null) return null;
  return int.parse(match[1] ?? match[2]!);
}

(int?, int?) _episodeNumbersOf(String title) {
  final match = _episodeNumbers.firstMatch(title);
  if (match == null) return (null, null);
  final end = match[2];
  return (
    int.parse(match[1] ?? match[3]!),
    end == null ? null : int.parse(end),
  );
}

/// One leaf's `file`: a URL, or several with a quality tag each.
List<AshdiStream> _files(String value, String? label) => [
  for (final (quality, url) in _splitQualities(value))
    if (url.contains('.m3u8'))
      AshdiStream(url: url, label: _join([label, quality])),
];

/// `subtitle` is labelled the way qualities are: `[Українські]a.vtt,...`
List<AshdiSubtitle> _subtitles(Object? value) {
  if (value is! String || value.trim().isEmpty) return const [];
  return [
    for (final (label, url) in _splitQualities(value))
      AshdiSubtitle(url: url, label: label),
  ];
}

/// `[720p]a.m3u8,[1080p]b.m3u8` -> `[('720p', 'a.m3u8'), ('1080p', 'b.m3u8')]`.
List<(String?, String)> _splitQualities(String value) {
  final tagged = [
    for (final match in _quality.allMatches(value))
      (match[1]!.trim(), match[2]!.trim()),
  ];
  if (tagged.isNotEmpty) return tagged;

  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) (null, part.trim()),
  ];
}

String? _join(List<String?> parts) {
  final kept = [
    for (final part in parts)
      if (part != null && part.trim().isNotEmpty) part.trim(),
  ];
  return kept.isEmpty ? null : kept.join(' / ');
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<AshdiStream> _dedupe(List<AshdiStream> streams) {
  final seen = <String>{};
  return [
    for (final stream in streams)
      if (seen.add(stream.url)) stream,
  ];
}
