/// Where a request goes so that a browser will make it.
///
/// A browser refuses a response from a host that does not name the page's own
/// origin, and refuses to let a page set `Referer`, `Origin` or `User-Agent` at
/// all. Both are the browser protecting the user from the page, and neither can
/// be argued with from inside the page — so the request is made somewhere else,
/// by something that is not a browser, and the answer comes back from an origin
/// the page is allowed to read.
///
/// The address carries the upstream in its *path* rather than in a query
/// parameter, and that is the whole reason this class exists:
///
/// ```
/// https://host/dir/index.m3u8   ->   /x/https/host/dir/index.m3u8
/// ```
///
/// An HLS playlist names its segments relatively — `seg-1.ts`, not the full
/// URL. Resolved against the proxied address that lands on
/// `/x/https/host/dir/seg-1.ts`, which is exactly right, and nothing had to
/// rewrite the playlist. A `?url=` parameter would resolve to `/seg-1.ts` and
/// every segment would 404.
abstract final class ProxyUrl {
  /// The path everything proxied hangs off. Short, so it stays readable in a
  /// network log next to a long stream URL.
  static const prefix = '/x';

  /// The header names a page is allowed to set, that the proxy turns back into
  /// the ones it is not.
  ///
  /// A browser drops `Referer` and `User-Agent` from `fetch` silently — the
  /// request goes out without them and the host answers 400 to something that
  /// looks nothing like its own player. These come through untouched and the
  /// proxy puts them back.
  static const refererHeader = 'x-proxy-referer';
  static const agentHeader = 'x-proxy-user-agent';

  /// The proxy's address for [url].
  ///
  /// [base] is empty when the proxy also serves the page, which is the usual
  /// case — the result is then same-origin and relative.
  static String encode(Uri url, {String base = ''}) {
    final head = '${url.scheme}://${url.authority}';
    final raw = url.toString();
    // Everything after the authority, still encoded exactly as it arrived.
    // Going through `Uri.path` instead would hand back a decoded path and
    // quietly turn `%2F` in a query-signed stream URL into a path separator.
    final tail = raw.startsWith(head) ? raw.substring(head.length) : '';
    return '$base$prefix/${url.scheme}/${url.authority}'
        '${tail.isEmpty ? '/' : tail}';
  }

  /// The upstream behind a proxied path, or `null` if it is not one.
  ///
  /// Takes the raw path-and-query — `request.uri.toString()` — rather than a
  /// parsed [Uri], for the same encoding reason as [encode].
  static Uri? decode(String pathAndQuery) {
    if (!pathAndQuery.startsWith('$prefix/')) return null;
    final rest = pathAndQuery.substring(prefix.length + 1);

    final schemeEnd = rest.indexOf('/');
    if (schemeEnd <= 0) return null;
    final scheme = rest.substring(0, schemeEnd);
    // Only the two web schemes: anything else is a request to open a `file:`
    // URL on the machine running the proxy.
    if (scheme != 'http' && scheme != 'https') return null;

    final afterScheme = rest.substring(schemeEnd + 1);
    final queryStart = afterScheme.indexOf('?');
    final beforeQuery = queryStart < 0
        ? afterScheme
        : afterScheme.substring(0, queryStart);
    final query = queryStart < 0 ? '' : afterScheme.substring(queryStart);

    final pathStart = beforeQuery.indexOf('/');
    final authority = pathStart < 0
        ? beforeQuery
        : beforeQuery.substring(0, pathStart);
    if (authority.isEmpty) return null;
    final path = pathStart < 0 ? '' : beforeQuery.substring(pathStart);

    final upstream = Uri.tryParse('$scheme://$authority$path$query');
    // A parse that loses the host — `https:///path` — is not something to send
    // a request to.
    if (upstream == null || upstream.host.isEmpty) return null;
    return upstream;
  }
}
