import 'package:iptv/iptv.dart';
import 'package:super_movies_api/super_movies_api.dart';

/// A channel on the ТБ screen, whichever it came from.
///
/// The two sources are not the same shape and should not be forced into one. A
/// playlist entry *is* a URL; a sweet.tv channel is an id that has to be traded
/// for a URL that expires. Flattening the second into the first would mean
/// storing a lease as though it were an address — which is exactly the bug that
/// would show up a day later as "the channel stopped working".
sealed class LiveChannel {
  const LiveChannel();

  /// Stable across restarts, and what favourites are keyed by.
  ///
  /// A playlist channel keeps using its URL, because that is what the store
  /// already holds — anything else would silently forget what somebody starred.
  String get id;

  String get name;
  String? get logoUrl;

  /// The chip this channel sits under.
  String? get group;

  /// Position on a remote's number pad, where the source says.
  int? get number;

  /// What is on right now, when the source knows. Playlists never do.
  String? get nowPlaying;

  /// Whether the schedule can be asked for. Only sweet.tv answers.
  bool get hasSchedule;
}

/// One line of somebody's M3U.
final class PlaylistChannel extends LiveChannel {
  const PlaylistChannel(this.channel);

  final IptvChannel channel;

  /// The stream URL, which is also the identity — two lists spell the same
  /// channel three ways, and only the URL says they are the same stream.
  @override
  String get id => channel.url;

  @override
  String get name => channel.name;

  @override
  String? get logoUrl => channel.logoUrl;

  @override
  String? get group => channel.group;

  @override
  int? get number => channel.number;

  @override
  String? get nowPlaying => null;

  @override
  bool get hasSchedule => false;

  /// Whether it will be blocked without a cleartext exception — the commonest
  /// reason a public list's channel shows nothing at all.
  bool get isCleartext => channel.isCleartext;
}

/// One of sweet.tv's free channels.
final class SweetLiveChannel extends LiveChannel {
  const SweetLiveChannel(this.channel, {this.categoryTitle});

  final TvChannel channel;

  /// The name of its first real category, resolved by whoever built the list —
  /// the channel itself carries only ids.
  final String? categoryTitle;

  /// Prefixed, so a numeric id can never collide with a playlist's URL.
  @override
  String get id => 'sweet:${channel.id}';

  @override
  String get name => channel.name;

  @override
  String? get logoUrl => channel.iconUrl;

  @override
  String? get group => categoryTitle;

  @override
  int? get number => null;

  @override
  String? get nowPlaying => channel.nowPlaying;

  @override
  bool get hasSchedule => true;
}
