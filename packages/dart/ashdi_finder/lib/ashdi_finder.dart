/// Reads the `.m3u8` streams and serial playlists out of an ashdi.vip player
/// page.
///
/// Parsing is pure string work ([extractStreams], [extractEpisodes]); fetching
/// is the caller's, through the [AshdiFetcher] an [AshdiResolver] is built
/// with. A Dart port of the Python `ashdi-finder` package.
library;

export 'src/models.dart';
export 'src/player.dart' show extractEpisodes, extractStreams;
export 'src/resolver.dart';
