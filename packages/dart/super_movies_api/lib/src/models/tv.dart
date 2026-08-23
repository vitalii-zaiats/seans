import '../json.dart';

/// A grouping the channel list offers as a chip.
final class TvCategory {
  const TvCategory({
    required this.id,
    required this.title,
    required this.isAll,
    this.slug,
  });

  factory TvCategory.fromJson(JsonMap json) {
    const owner = 'TvCategory';
    return TvCategory(
      id: json.requireInt('id', owner: owner),
      title: json.requireString('title', owner: owner),
      isAll: json.boolOr('is_all'),
      slug: json.stringOrNull('slug'),
    );
  }

  final int id;
  final String title;

  /// Absent on the "all" pseudo-category, the one without a page of its own.
  final String? slug;
  final bool isAll;

  @override
  String toString() => 'TvCategory($id, $title)';
}

/// One free channel.
final class TvChannel {
  const TvChannel({
    required this.id,
    required this.slug,
    required this.name,
    this.iconUrl,
    this.bannerUrl,
    this.colour,
    this.categories = const [],
    this.catchupDays = 0,
    this.nowPlaying,
  });

  factory TvChannel.fromJson(JsonMap json) {
    const owner = 'TvChannel';
    return TvChannel(
      id: json.requireInt('id', owner: owner),
      slug: json.requireString('slug', owner: owner),
      name: json.requireString('name', owner: owner),
      iconUrl: json.stringOrNull('icon_url'),
      bannerUrl: json.stringOrNull('banner_url'),
      colour: json.stringOrNull('colour'),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<int>()
          .toList(growable: false),
      catchupDays: json['catchup_days'] is int
          ? json['catchup_days'] as int
          : 0,
      nowPlaying: json.stringOrNull('now_playing'),
    );
  }

  final int id;
  final String slug;
  final String name;

  /// Already https — the API rewrites the plain-http address the upstream
  /// catalogue hands out, which a page on https would refuse as mixed content.
  final String? iconUrl;
  final String? bannerUrl;
  final String? colour;
  final List<int> categories;

  /// How many days back the archive goes; `0` for live only.
  final int catchupDays;

  /// What is on right now, with no times. It comes free with the list, so a
  /// whole grid can say what is on without one request per row.
  final String? nowPlaying;

  bool get hasCatchup => catchupDays > 0;

  @override
  String toString() => 'TvChannel($id, $name)';
}

/// The whole free list, in one answer.
final class TvChannels {
  const TvChannels({this.items = const [], this.categories = const []});

  factory TvChannels.fromJson(JsonMap json) => TvChannels(
    items: json.listOf('items', TvChannel.fromJson),
    categories: json.listOf('categories', TvCategory.fromJson),
  );

  final List<TvChannel> items;

  /// In the order the site shows them, which is not the order they arrive in.
  final List<TvCategory> categories;

  List<TvChannel> inCategory(int id) =>
      items.where((one) => one.categories.contains(id)).toList(growable: false);
}

/// One programme in a channel's day.
final class TvProgramme {
  const TvProgramme({
    required this.id,
    required this.title,
    required this.start,
    required this.stop,
    this.available = true,
  });

  factory TvProgramme.fromJson(JsonMap json) {
    const owner = 'TvProgramme';
    return TvProgramme(
      id: json.requireInt('id', owner: owner),
      title: json.requireString('title', owner: owner),
      start: json.requireDateTime('start', owner: owner),
      stop: json.requireDateTime('stop', owner: owner),
      available: json.boolOr('available', fallback: true),
    );
  }

  final int id;
  final String title;
  final DateTime start;
  final DateTime stop;

  /// Whether the archive holds it. False for programmes rights do not cover.
  final bool available;

  Duration get length => stop.difference(start);

  bool isOnAt(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(stop);

  /// 0–1 through this programme, clamped. Where the bar under "now" comes from.
  double progressAt(DateTime moment) {
    final total = length.inSeconds;
    if (total <= 0) return 0;
    final done = moment.difference(start).inSeconds / total;
    return done < 0 ? 0 : (done > 1 ? 1 : done);
  }

  @override
  String toString() => 'TvProgramme($title)';
}

/// A channel's programmes for one day.
final class TvSchedule {
  const TvSchedule({
    required this.channelId,
    required this.day,
    this.items = const [],
  });

  factory TvSchedule.fromJson(JsonMap json) {
    const owner = 'TvSchedule';
    return TvSchedule(
      channelId: json.requireInt('channel_id', owner: owner),
      day: json.requireDateTime('day', owner: owner),
      items: json.listOf('items', TvProgramme.fromJson),
    );
  }

  final int channelId;
  final DateTime day;
  final List<TvProgramme> items;

  /// What is on, or `null` outside the day this covers.
  TvProgramme? onAt(DateTime moment) {
    for (final one in items) {
      if (one.isOnAt(moment)) return one;
    }
    return null;
  }

  /// What follows.
  ///
  /// `null` inside the last programme of the day — the next one belongs to
  /// tomorrow's answer, and this does not stitch two days together behind the
  /// caller's back.
  TvProgramme? afterAt(DateTime moment) {
    for (var index = 0; index < items.length; index++) {
      if (items[index].isOnAt(moment)) {
        return index + 1 < items.length ? items[index + 1] : null;
      }
    }
    // Between programmes, or before the first: the next one to start.
    for (final one in items) {
      if (one.start.isAfter(moment)) return one;
    }
    return null;
  }

  bool get isEmpty => items.isEmpty;
}

/// A lease on a channel's stream — not an address.
///
/// It carries a session and goes stale after [refreshIn]. Store the channel id
/// and ask again; do not store the URL.
final class TvStream {
  const TvStream({
    required this.channelId,
    required this.url,
    required this.refreshIn,
    this.plainUrl,
    this.directUrl,
  });

  factory TvStream.fromJson(JsonMap json) {
    const owner = 'TvStream';
    return TvStream(
      channelId: json.requireInt('channel_id', owner: owner),
      url: json.requireString('url', owner: owner),
      refreshIn: Duration(seconds: json.requireInt('refresh_in', owner: owner)),
      plainUrl: json.stringOrNull('plain_url'),
      directUrl: json.stringOrNull('direct_url'),
    );
  }

  final int channelId;
  final String url;

  /// The same stream over plain http. On Android it is the one that works: the
  /// stitching host presents a chain ending in the old Go Daddy Class 2 root
  /// signed with SHA-1, which Android rejects outright.
  final String? plainUrl;

  /// Without the ad stitching, offered for casting. Undocumented upstream.
  final String? directUrl;

  final Duration refreshIn;

  @override
  String toString() => 'TvStream($channelId, ${refreshIn.inSeconds}s)';
}
