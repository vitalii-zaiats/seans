import 'proxy_url.dart';

/// Whether a response is an HLS playlist, and so worth reading before passing
/// on.
///
/// Content type first, because it is the thing that is actually declared; the
/// extension is the fallback for a CDN that serves `application/octet-stream`
/// and lets the player work it out.
bool looksLikePlaylist({String? contentType, required String path}) {
  final type = contentType?.toLowerCase() ?? '';
  if (type.contains('mpegurl')) return true;
  return path.toLowerCase().endsWith('.m3u8');
}

/// A playlist with every address in it pointed back at the proxy.
///
/// A relative name needs nothing done to it — the proxied address keeps the
/// upstream's directory structure, so `seg-1.ts` resolves correctly on its own.
/// An absolute one does: ashdi's master playlist names each variant in full,
/// and a player following those would leave this origin and hit exactly the
/// wall the proxy exists to get around. That is not a hypothetical — it is what
/// ashdi actually sends.
String rewritePlaylist(String body, {String base = ''}) {
  final lines = body.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    if (trimmed.startsWith('#')) {
      // A key or an initialisation segment is named inside the tag rather than
      // on a line of its own, and an encrypted stream that cannot fetch its key
      // plays nothing at all.
      lines[i] = _rewriteUris(line, base);
      continue;
    }

    lines[i] = _rewrite(trimmed, base) ?? line;
  }

  return lines.join('\n');
}

/// `URI="..."` wherever it appears in a tag.
String _rewriteUris(String line, String base) =>
    line.replaceAllMapped(RegExp(r'URI="([^"]*)"'), (match) {
      final rewritten = _rewrite(match[1]!, base);
      return rewritten == null ? match[0]! : 'URI="$rewritten"';
    });

/// The proxied form of an absolute address, or `null` when there is nothing to
/// do — which is the common case and has to stay cheap.
String? _rewrite(String value, String base) {
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    return null;
  }
  final url = Uri.tryParse(value);
  if (url == null || url.host.isEmpty) return null;
  return ProxyUrl.encode(url, base: base);
}
