import 'dart:convert';

/// Performs one DoH query and returns the body as text.
///
/// This package makes no requests of its own. Hand it something that does, and
/// timeouts and headers stay in the application where they belong; a test hands
/// it a canned string.
typedef DohFetcher = Future<String> Function(Uri url);

/// A resolver that answers over HTTPS.
class DohServer {
  const DohServer({required this.name, required this.endpoint});

  final String name;

  /// Addressed **by IP**, on purpose: a resolver whose own name has to be
  /// resolved first is a resolver that cannot be used when DNS is the problem.
  /// Both of the built-in ones carry their address in the certificate, so this
  /// is still a verified connection and not a shortcut around one.
  final String endpoint;

  Uri query(String host) => Uri.parse('$endpoint?name=$host&type=A');

  static const cloudflare = DohServer(
    name: 'Cloudflare',
    endpoint: 'https://1.1.1.1/dns-query',
  );

  static const google = DohServer(
    name: 'Google',
    endpoint: 'https://8.8.8.8/resolve',
  );

  /// Tried in order. Two, so one being unreachable is not the end of it.
  static const defaults = [cloudflare, google];
}

/// Turns names into addresses over HTTPS.
///
/// Not a fix for a blocked site — a name that resolves is not a site that
/// answers — but it takes the network's own resolver out of the question,
/// which on a home connection is the part somebody else controls.
class DohResolver {
  DohResolver({
    required this.fetch,
    this.servers = DohServer.defaults,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final DohFetcher fetch;
  final List<DohServer> servers;
  final DateTime Function() _now;

  final _cache = <String, _Answer>{};

  /// Never trust a TTL of seconds — a resolver that says `1` would have this
  /// asking again on every connection.
  static const _floor = Duration(seconds: 30);
  static const _ceiling = Duration(hours: 1);

  /// Addresses for [host], or an empty list when nothing answered.
  ///
  /// Empty rather than an exception: the caller's fallback is the ordinary
  /// system resolver, and a name that could not be looked up this way is not
  /// an error worth interrupting anything for.
  Future<List<String>> resolve(String host) async {
    final cached = _cache[host];
    if (cached != null && cached.until.isAfter(_now())) return cached.addresses;

    for (final server in servers) {
      final answer = await _ask(server, host);
      if (answer == null || answer.addresses.isEmpty) continue;

      _cache[host] = answer;
      return answer.addresses;
    }

    return const [];
  }

  /// Drops what was remembered for [host] — for when an address stops working
  /// and the next attempt should ask again rather than reuse it.
  void forget(String host) => _cache.remove(host);

  void clear() => _cache.clear();

  Future<_Answer?> _ask(DohServer server, String host) async {
    final String body;
    try {
      body = await fetch(server.query(host));
    } on Object {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    // 0 is NOERROR. Anything else — NXDOMAIN, SERVFAIL — is an answer saying
    // there is nothing, and trying the next resolver is worth a try.
    if ((decoded['Status'] as num?)?.toInt() != 0) return null;

    final addresses = <String>[];
    var ttl = _ceiling;

    for (final entry in decoded['Answer'] as List? ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      // Type 1 is A. A reply also carries the CNAMEs it walked through, and
      // those are names, not addresses.
      if ((entry['type'] as num?)?.toInt() != 1) continue;

      final data = entry['data'] as String?;
      if (data == null || data.isEmpty) continue;
      addresses.add(data);

      final seconds = (entry['TTL'] as num?)?.toInt();
      if (seconds != null) {
        final each = Duration(seconds: seconds);
        if (each < ttl) ttl = each;
      }
    }

    if (addresses.isEmpty) return null;

    final held = ttl < _floor ? _floor : (ttl > _ceiling ? _ceiling : ttl);
    return _Answer(addresses: addresses, until: _now().add(held));
  }
}

class _Answer {
  const _Answer({required this.addresses, required this.until});

  final List<String> addresses;
  final DateTime until;
}
