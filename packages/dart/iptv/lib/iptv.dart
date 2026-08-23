/// Reads M3U playlists into channels.
///
/// Parsing is pure string work ([parsePlaylist]); fetching is the caller's,
/// through the [PlaylistFetcher] an [IptvLoader] is built with. Same shape as
/// `ashdi_finder`, and for the same reason.
library;

export 'src/channel.dart';
export 'src/parser.dart' show IptvPlaylist, parsePlaylist;
export 'src/source.dart';
