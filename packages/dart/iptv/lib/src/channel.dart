/// One channel from an M3U playlist.
class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logoUrl,
    this.tvgId,
    this.group,
    this.number,
    this.country,
  });

  /// What the playlist calls it, from after the comma on the `#EXTINF` line.
  final String name;

  /// The stream. Usually HLS, occasionally a progressive URL.
  final String url;

  final String? logoUrl;

  /// Programme-guide id, for pairing with an XMLTV feed later.
  final String? tvgId;

  /// `group-title`, which lists use for country or genre — there is no
  /// convention, so it is whatever the list's author decided.
  final String? group;

  /// `tvg-chno`, the channel's position on a remote's number pad.
  final int? number;

  /// ISO country code, when the list bothers.
  final String? country;

  /// Whether this looks like an HLS stream, which is all the player handles.
  bool get isHls => url.contains('.m3u8');

  /// Whether it will be blocked on Android without a cleartext exception.
  ///
  /// A good share of public lists still carry plain-HTTP streams, and on a
  /// modern box those fail with nothing on screen to explain why.
  bool get isCleartext => url.startsWith('http://');

  @override
  bool operator ==(Object other) =>
      other is IptvChannel && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(url, name);

  @override
  String toString() => 'IptvChannel($name)';
}
