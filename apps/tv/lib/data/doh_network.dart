import 'dart:convert';
import 'dart:io';

import 'package:doh/doh.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP that looks names up over HTTPS instead of asking the network.
///
/// The socket is opened to an address this app resolved; the certificate is
/// still checked against the *name* that was asked for, because that is what
/// `dart:io` uses for the handshake regardless of where the socket went. So
/// this changes who answers "where is it", and nothing about who is trusted —
/// verified, not assumed.
///
/// Not a way past a blocked site. A name that resolves is not a site that
/// answers, and anything sitting in the middle of the connection is still
/// sitting there.
class DohNetwork {
  DohNetwork() {
    _plain = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);

    _resolver = DohResolver(fetch: _query);
  }

  late final HttpClient _plain;
  late final DohResolver _resolver;

  final _clients = <HttpClient>[];

  /// A client that resolves over HTTPS, falling back to the ordinary resolver
  /// whenever that fails.
  ///
  /// The fallback is the point: a box where the DoH resolvers are themselves
  /// unreachable has to keep working, and silently doing nothing would be the
  /// worst of both.
  http.Client client() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (uri, proxyHost, proxyPort) async {
        final host = proxyHost ?? uri.host;
        final port = proxyPort ?? uri.port;

        final target = await _addressFor(host);
        return Socket.startConnect(target, port);
      };

    _clients.add(io);
    return IOClient(io);
  }

  Future<String> _addressFor(String host) async {
    // An address is already an answer; asking a resolver about `1.1.1.1` would
    // be asking it about itself.
    if (InternetAddress.tryParse(host) != null) return host;

    final addresses = await _resolver.resolve(host);
    return addresses.isEmpty ? host : addresses.first;
  }

  /// The DoH request itself, which must not go through DoH.
  Future<String> _query(Uri url) async {
    final request = await _plain.getUrl(url);
    request.headers.set('accept', 'application/dns-json');

    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw HttpException('resolver answered ${response.statusCode}', uri: url);
    }
    return response.transform(utf8.decoder).join();
  }

  void close() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
    _plain.close(force: true);
  }
}
