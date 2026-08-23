import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:super_movies_api/super_movies_api.dart';

/// Where the box appears to be, and how well it is connected.
class NetworkReport {
  const NetworkReport({
    required this.ip,
    required this.countryCode,
    required this.countryName,
    required this.isp,
    required this.catalogueReachable,
    required this.megabitsPerSecond,
  });

  final String? ip;

  /// ISO code, e.g. `UA`. `null` when the lookup failed.
  final String? countryCode;

  final String? countryName;
  final String? isp;

  /// Whether the catalogue answered at all — a different question from
  /// throughput, and the one geo-blocking shows up in.
  final bool catalogueReachable;

  /// Measured throughput, or `null` when it could not be measured.
  final double? megabitsPerSecond;

  /// The service is licensed for Ukraine, so anywhere else is worth warning
  /// about even when the catalogue happens to answer.
  bool get isInUkraine => countryCode == 'UA';

  /// Nothing to say about the location, so say nothing rather than guess.
  bool get locationUnknown => countryCode == null;

  /// Enough for a 1080p stream with headroom.
  bool get isFastEnough => megabitsPerSecond != null && megabitsPerSecond! >= 8;

  /// Nothing answered at all.
  ///
  /// Three independent hosts failing together is a box with no network, not a
  /// catalogue that is blocked — and the two want telling apart, because only
  /// one of them is fixed by joining a Wi-Fi.
  bool get isOffline =>
      countryCode == null && !catalogueReachable && megabitsPerSecond == null;
}

/// Answers the three questions the setup screen asks: where is this box, can
/// it reach the catalogue, and how fast is the line.
class NetworkProbe {
  NetworkProbe({http.Client? client, SuperMoviesApi? api})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _api = api;

  /// Free, keyless and HTTPS — the last of which matters, because Android
  /// blocks cleartext by default and this app declares no exception.
  static final geoUrl = Uri.parse('https://ipwho.is/');

  /// Hetzner's public test file, from a German site rather than their
  /// American one: a box in Ukraine reaches Nuremberg over the same sort of
  /// path it reaches the catalogue's CDN over, while Ashburn measures the
  /// Atlantic.
  static final speedUrl = Uri.parse('https://nbg1-speed.hetzner.com/1GB.bin');

  /// Stops early on a fast line, and the time cap stops it on a slow one, so
  /// this never eats more of somebody's connection than it has to.
  static const _byteCap = 24 * 1024 * 1024;
  static const _timeCap = Duration(seconds: 5);

  final http.Client _client;
  final bool _ownsClient;
  final SuperMoviesApi? _api;

  Future<NetworkReport> run() async {
    // Sequential on purpose: measuring throughput while other requests are in
    // flight measures the wrong thing.
    final geo = await _geo();
    final reachable = await _catalogueReachable();
    final speed = await measureThroughput();

    return NetworkReport(
      ip: geo?['ip'] as String?,
      countryCode: geo?['country_code'] as String?,
      countryName: geo?['country'] as String?,
      isp: (geo?['connection'] as Map<String, dynamic>?)?['isp'] as String?,
      catalogueReachable: reachable,
      megabitsPerSecond: speed,
    );
  }

  Future<Map<String, dynamic>?> _geo() async {
    try {
      final response = await _client
          .get(geoUrl)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return decoded['success'] == false ? null : decoded;
    } on Object {
      // A location this could not determine is an ordinary answer here.
      return null;
    }
  }

  Future<bool> _catalogueReachable() async {
    final api = _api;
    if (api == null) return false;
    try {
      await api.catalogFilters();
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Pulls a capped slice of a known test file and times it.
  ///
  /// Streamed and counted as it arrives rather than awaited whole, so the time
  /// cap can cut it off mid-download on a slow line instead of hanging.
  Future<double?> measureThroughput() async {
    final request = http.Request('GET', speedUrl)
      ..headers['Range'] = 'bytes=0-${_byteCap - 1}';

    StreamSubscription<List<int>>? subscription;
    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 && response.statusCode != 206) {
        return null;
      }

      final done = Completer<void>();
      var bytes = 0;
      final started = DateTime.now();

      subscription = response.stream.listen(
        (chunk) {
          bytes += chunk.length;
          if (bytes >= _byteCap && !done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      await done.future.timeout(_timeCap, onTimeout: () {});
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;

      if (bytes == 0 || seconds <= 0) return null;
      return bytes * 8 / seconds / 1000000;
    } on Object {
      return null;
    } finally {
      await subscription?.cancel();
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
