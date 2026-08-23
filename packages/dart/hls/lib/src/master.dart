/// One quality an HLS stream is offered in.
class HlsVariant {
  const HlsVariant({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.bandwidth = 0,
    this.codecs = '',
    this.frameRate = 0,
  });

  /// Absolute, resolved against the master playlist's own address — a variant
  /// line is very often a bare file name.
  final String url;

  final int width;
  final int height;

  /// Bits per second the playlist claims. What a player picks by when two
  /// variants share a resolution.
  final int bandwidth;

  final String codecs;
  final double frameRate;

  bool get hasSize => width > 0 && height > 0;

  /// `1080p`, or the bitrate when the playlist did not say the size.
  String get label {
    if (hasSize) return '${height}p';
    if (bandwidth > 0) {
      return '${(bandwidth / 1000000).toStringAsFixed(1)} Мбіт';
    }
    return 'Потік';
  }

  @override
  String toString() => 'HlsVariant($label)';
}

/// What a master playlist offers.
class HlsMaster {
  const HlsMaster(this.variants);

  /// Highest first, so the best is the obvious default and a list reads the
  /// way people expect.
  final List<HlsVariant> variants;

  bool get isEmpty => variants.isEmpty;

  /// The best variant a screen [height] pixels tall can actually show.
  ///
  /// Pulling 1080p onto a 720p panel spends bandwidth and decoder on detail
  /// that is thrown away before it reaches the glass. Falls back to the
  /// smallest when everything on offer is bigger than the screen — something
  /// has to play.
  HlsVariant? bestFor(int height) {
    if (variants.isEmpty) return null;

    for (final variant in variants) {
      if (!variant.hasSize || variant.height <= height) return variant;
    }
    return variants.last;
  }
}

/// Reads a master playlist.
///
/// Returns an empty master for anything that is not one — a media playlist
/// (segments rather than variants) has no qualities to choose between, and
/// that is an ordinary answer rather than an error.
HlsMaster parseMaster(String body, {Uri? base}) {
  final variants = <HlsVariant>[];
  final lines = body.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

    // The URL is the next line that is neither blank nor a tag. Players are
    // expected to skip comments between the two, and some playlists have them.
    String? target;
    for (var j = i + 1; j < lines.length; j++) {
      final next = lines[j].trim();
      if (next.isEmpty || next.startsWith('#')) continue;
      target = next;
      break;
    }
    if (target == null) continue;

    final attributes = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
    final resolution = attributes['RESOLUTION']?.split('x');

    variants.add(
      HlsVariant(
        url: _resolve(target, base),
        width: resolution == null ? 0 : int.tryParse(resolution.first) ?? 0,
        height: resolution == null || resolution.length < 2
            ? 0
            : int.tryParse(resolution[1]) ?? 0,
        bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
        codecs: attributes['CODECS'] ?? '',
        frameRate: double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0,
      ),
    );
  }

  variants.sort((a, b) {
    final size = b.height.compareTo(a.height);
    return size != 0 ? size : b.bandwidth.compareTo(a.bandwidth);
  });

  return HlsMaster(variants);
}

/// Splits `BANDWIDTH=123,CODECS="a,b",RESOLUTION=1x2` without breaking on the
/// comma inside the quotes.
Map<String, String> _attributes(String line) {
  final found = <String, String>{};
  var start = 0;
  var quoted = false;

  void take(int end) {
    final pair = line.substring(start, end);
    final equals = pair.indexOf('=');
    if (equals <= 0) return;

    final key = pair.substring(0, equals).trim().toUpperCase();
    var value = pair.substring(equals + 1).trim();
    if (value.length > 1 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    found[key] = value;
  }

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      quoted = !quoted;
    } else if (char == ',' && !quoted) {
      take(i);
      start = i + 1;
    }
  }
  take(line.length);

  return found;
}

String _resolve(String target, Uri? base) {
  if (base == null) return target;
  if (target.startsWith('http://') || target.startsWith('https://')) {
    return target;
  }
  return base.resolve(target).toString();
}
