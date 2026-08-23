import 'dart:io';

/// What the box actually got when a handshake failed.
///
/// A refused certificate has two very different causes that look identical
/// from inside the app: the real certificate is one nothing trusts, or
/// something on the way is answering in the host's place — a provider's block
/// page, a captive portal, a router doing interception. The certificate itself
/// says which, and so does the address it resolved to.
///
/// Nothing here ever accepts a certificate. The callback returns `false` every
/// time; it is only used to read what was offered before the connection dies.
class TlsReport {
  const TlsReport({
    required this.host,
    this.addresses = const [],
    this.subject,
    this.issuer,
    this.error,
  });

  final String host;

  /// What the box's own resolver returned. A different answer from what the
  /// rest of the world sees is the whole diagnosis.
  final List<String> addresses;

  /// Who the certificate was issued to, and by whom.
  final String? subject;
  final String? issuer;

  final String? error;

  /// Whether the certificate names the host it was asked for.
  ///
  /// A block page's certificate names the provider, not the site — which is
  /// the difference between "nobody trusts this root" and "this is not the
  /// site at all".
  bool get matchesHost {
    final name = subject;
    if (name == null) return false;

    final common = RegExp(r'CN=([^,/]+)').firstMatch(name)?.group(1)?.trim();
    if (common == null) return false;

    final bare = common.startsWith('*.') ? common.substring(2) : common;
    return host == bare || host.endsWith('.$bare');
  }

  /// One line for a television screen.
  String get summary {
    final where = addresses.isEmpty
        ? 'адреса не визначилась'
        : addresses.join(', ');
    if (subject == null) return '$host → $where · сертифікат не отримано';

    return '$host → $where\n'
        'сертифікат: $subject\n'
        'видав: $issuer';
  }
}

/// Asks a host for its certificate without ever accepting it.
Future<TlsReport> probeTls(String host, {int port = 443}) async {
  final addresses = <String>[];
  try {
    for (final address in await InternetAddress.lookup(host)) {
      addresses.add(address.address);
    }
  } on SocketException catch (error) {
    return TlsReport(host: host, error: error.message);
  }

  String? subject;
  String? issuer;
  String? failure;

  try {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
      onBadCertificate: (certificate) {
        subject = certificate.subject;
        issuer = certificate.issuer;
        // Never true. This reads what was offered; it does not accept it.
        return false;
      },
    );
    // A handshake that succeeds here means the certificate was fine after all.
    await socket.close();
  } on Object catch (error) {
    failure = error.toString().split('\n').first;
  }

  return TlsReport(
    host: host,
    addresses: addresses,
    subject: subject,
    issuer: issuer,
    error: failure,
  );
}
