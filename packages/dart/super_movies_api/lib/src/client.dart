import 'dart:async';
import 'dart:convert';

import 'decode.dart';
import 'exceptions.dart';
import 'http_transport.dart';
import 'json.dart';
import 'models/account.dart';
import 'models/catalogue.dart';
import 'models/details.dart';
import 'models/device_link.dart';
import 'models/launch.dart';
import 'models/playback.dart';
import 'models/start.dart';
import 'models/tv.dart';
import 'transport.dart';

/// Client for the Super Movies API.
///
/// ```dart
/// final api = SuperMoviesApi(baseUrl: Uri.parse('https://api.supermovies.example'));
///
/// final start = await api.start(Launch.identified(
///   installId: installId,          // generated once, kept in storage
///   platform: AppPlatform.android,
///   vendor: installerPackage,      // null unless android
///   version: '1.0.0',
/// ));
///
/// if (start.update.isRequired) return showUpdateWall(start.update);
/// ```
///
/// **The token looks after itself.** Every call that creates or rotates a
/// session stores it here and sends it afterwards. That matters most for
/// [claim], which deliberately rotates the token — a client that kept the old
/// one by hand would be signed out at the exact moment it gained an account.
/// Pass [onToken] to persist it, and [token] on the way back in.
///
/// Every method throws an [ApiException] subclass on failure:
/// [ApiHttpException] for a non-2xx status, [ApiNetworkException] when the
/// request never completed, [ApiSerializationException] when the payload is no
/// longer the shape this package expects.
final class SuperMoviesApi {
  SuperMoviesApi({
    required this.baseUrl,
    Transport? transport,
    String? token,
    void Function(String? token)? onToken,
    Map<String, String>? headers,
    this.timeout = const Duration(seconds: 20),
  }) : _transport = transport ?? HttpTransport(),
       _token = token,
       _onToken = onToken,
       _headers = {'Accept': 'application/json', ...?headers};

  /// Root every path is appended to. A trailing slash is ignored.
  final Uri baseUrl;

  /// Applied per request; exceeding it fails with [ApiNetworkException].
  final Duration timeout;

  final Transport _transport;
  final Map<String, String> _headers;
  final void Function(String? token)? _onToken;

  String? _token;

  /// The session token this client is holding, if any.
  String? get token => _token;

  /// Replaces it — on restart, from wherever the app persisted it.
  set token(String? value) {
    if (_token == value) return;
    _token = value;
    _onToken?.call(value);
  }

  /// Whether this client is carrying an identity at all.
  bool get isSignedIn => _token != null;

  // --- starting up ---------------------------------------------------------

  /// `POST /init` — announce this launch and collect everything it needs.
  ///
  /// Safe on every start: the install row is updated rather than duplicated,
  /// and a token already held is kept rather than replaced. Build [launch] with
  /// [Launch.anonymous] to be told nothing is written down.
  Future<Start> start(Launch launch) async {
    final result = Start.fromJson(await _post('/init', launch.toJson()));
    final issued = result.session?.token;
    if (issued != null) token = issued;
    return result;
  }

  // --- identity ------------------------------------------------------------

  /// `GET /auth/me` — who the token belongs to.
  ///
  /// Throws [ApiHttpException] with `isUnauthorized` when there is no token or
  /// it has gone stale. It never creates an account as a side effect; becoming
  /// somebody is always an explicit call.
  Future<Account> me() async => Account.fromJson(await _get('/auth/me'));

  /// `POST /auth/guest` — a guest, on demand.
  ///
  /// For a client with no install to announce. Unconditional: calling it while
  /// already signed in starts a *second*, empty identity rather than handing
  /// back the first.
  Future<Identity> becomeGuest() async =>
      _remember(Identity.fromJson(await _post('/auth/guest', const {})));

  /// `POST /auth/claim` — put a name on the guest you already are.
  ///
  /// Everything watched as a guest stays where it is. The token is rotated;
  /// this client swaps to the new one for you.
  Future<Identity> claim({
    required String email,
    required String password,
    String? displayName,
  }) async => _remember(
    Identity.fromJson(
      await _post('/auth/claim', {
        'email': email,
        'password': password,
        'display_name': ?displayName,
      }),
    ),
  );

  /// `POST /auth/register` — an account with no guest behind it.
  ///
  /// For somebody who ran the app anonymously and only now wants to be
  /// remembered: there is no history to keep, so making a guest first and
  /// claiming it would be theatre.
  Future<Identity> register({
    required String email,
    required String password,
    String? displayName,
  }) async => _remember(
    Identity.fromJson(
      await _post('/auth/register', {
        'email': email,
        'password': password,
        'display_name': ?displayName,
      }),
    ),
  );

  /// `POST /auth/login`.
  Future<Identity> signIn({
    required String email,
    required String password,
  }) async => _remember(
    Identity.fromJson(
      await _post('/auth/login', {'email': email, 'password': password}),
    ),
  );

  /// `POST /auth/logout` — revokes this token server-side and forgets it here.
  Future<void> signOut() async {
    await _send('POST', '/auth/logout');
    token = null;
  }

  /// `PATCH /auth/me`.
  Future<Account> rename(String displayName) async => Account.fromJson(
    await _send('PATCH', '/auth/me', body: {'display_name': displayName}),
  );

  /// `DELETE /auth/me` — the way back to anonymous.
  ///
  /// Deletes the account and every session on it. There is no undo: an account
  /// somebody asked us to forget is not one we keep a copy of.
  Future<void> forget() async {
    await _send('DELETE', '/auth/me');
    token = null;
  }

  // --- signing in a device with no keyboard --------------------------------

  /// `POST /auth/device` — begin a pairing.
  ///
  /// Typing an email with a D-pad is miserable, so this device never asks for
  /// one. Show [DeviceLink.code] and a QR of [DeviceLink.verifyUrl]; a phone
  /// opens it, signs in as itself, and approves. Then [collectDeviceLink].
  ///
  /// Nothing worth stealing crosses the room: the code only lets somebody
  /// approve, and [DeviceLink.secret] — which never leaves here — is the only
  /// thing that can collect.
  ///
  /// [deviceName] is what the phone shows before somebody approves — `Android
  /// TV`, `macOS`. Proof of nothing, and that is fine: it is there so a person
  /// approving two boxes can tell which is which. Omit it and the server falls
  /// back to the `User-Agent`, which on the web is a paragraph of browser
  /// trivia and on a box is barely better. At most 80 characters; longer is
  /// refused rather than quietly cut, because this is a value the caller chose.
  Future<DeviceLink> startDeviceLink({String? deviceName}) async =>
      DeviceLink.fromJson(
        await _post('/auth/device', {
          if (deviceName != null && deviceName.trim().isNotEmpty)
            'device_name': deviceName.trim(),
        }),
      );

  /// `GET /auth/device/{code}` — what is being asked for, for the page about to
  /// say yes.
  Future<DeviceLinkStatus> deviceLink(String code) async =>
      DeviceLinkStatus.fromJson(await _get('/auth/device/$code'));

  /// `POST /auth/device/approve` — say yes, as whoever this client is signed in
  /// as. The phone calls this, never the television.
  Future<DeviceLinkStatus> approveDeviceLink(String code) async =>
      DeviceLinkStatus.fromJson(
        await _post('/auth/device/approve', {'code': code}),
      );

  /// `POST /auth/device/collect` — has anybody said yes yet?
  ///
  /// `null` means "not yet", which is the ordinary answer while somebody walks
  /// to their phone. An [Identity] is final, and this client swaps to its token.
  /// Collecting works once: a token handed out twice is one that can be
  /// replayed.
  Future<Identity?> collectDeviceLink(String secret) async {
    final answer = await _post('/auth/device/collect', {'secret': secret});
    final identity = answer.mapOrNull('identity');
    if (answer.stringOrNull('status') != 'linked' || identity == null) {
      return null;
    }
    return _remember(Identity.fromJson(identity));
  }

  /// Polls [collectDeviceLink] until somebody approves, the code expires,
  /// [timeout] runs out, or [until] completes. `null` means none of the above
  /// ended in an identity.
  ///
  /// A poll rather than a push on purpose: the pairing has to work when the
  /// only thing between the two devices is this API.
  ///
  /// **Pass [until] from anything that can go away.** Without it this runs to
  /// the deadline whatever happens to the caller — and the caller is a screen.
  /// Somebody who opened the pairing page in a browser and left it went on
  /// asking `/auth/device/collect` every two seconds for ten minutes, three
  /// hundred requests for a code nobody was going to approve. Awaiting a
  /// `Future` cannot cancel it; the loop has to be told.
  Future<Identity?> awaitDeviceLink(
    String secret, {
    Duration every = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 10),
    Future<void>? until,
  }) async {
    var stopped = false;
    // Watched rather than awaited: the loop has to keep running until it fires.
    unawaited(until?.then((_) => stopped = true));

    final deadline = DateTime.now().add(timeout);
    while (!stopped && DateTime.now().isBefore(deadline)) {
      final identity = await collectDeviceLink(secret);
      if (identity != null) return identity;
      if (stopped) break;

      // Raced, not just checked afterwards: a plain `delayed` would hold the
      // loop open for another two seconds past the moment it was told to stop,
      // and on a screen that has already gone that is two seconds of requests
      // nobody will read.
      await Future.any([Future<void>.delayed(every), ?until]);
    }
    return null;
  }

  // --- the catalogue -------------------------------------------------------

  /// `GET /catalogue/content` — a page of the catalogue.
  ///
  /// [genres] and [year] take **slugs** from [catalogFilters], not display
  /// names — `bojovik`, `2006-2010`.
  Future<Paginated<ContentCard>> catalog({
    ContentType? type,
    int? page,
    List<String>? genres,
    String? year,
  }) async => Paginated.fromJson(
    await _get(
      _query('/catalogue/content', {
        'type': type?.slug,
        'page': page?.toString(),
        'genres': genres,
        'year': year,
      }),
    ),
    ContentCard.fromJson,
  );

  /// `GET /catalogue/filters` — genres and year buckets per section.
  ///
  /// Held server-side, so asking on every catalogue screen costs nothing.
  Future<CatalogFilters> catalogFilters() async =>
      CatalogFilters.fromJson(await _get('/catalogue/filters'));

  /// `GET /catalogue/trending` — a home rail, richer than a catalogue card.
  Future<List<ContentCard>> trending({ContentType? type}) async =>
      _cards(await _get(_query('/catalogue/trending', {'type': type?.slug})));

  /// `GET /catalogue/slider` — the hero row, with trailer ids and age ratings.
  Future<List<ContentCard>> slider({ContentType? type}) async =>
      _cards(await _get(_query('/catalogue/slider', {'type': type?.slug})));

  /// `GET /catalogue/search` — titles matching [query].
  ///
  /// Anything under two characters short-circuits here rather than costing a
  /// round trip, which is what makes this safe to call on every keystroke.
  Future<List<SearchResult>> search(String query, {int? limit}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    final answer = await _get(
      _query('/catalogue/search', {'q': trimmed, 'limit': limit?.toString()}),
    );
    return answer.listOf('items', SearchResult.fromJson);
  }

  /// `POST /catalogue/cards` — cards for several slugs in one round trip.
  ///
  /// What a stored watchlist and "continue watching" render from. The answer
  /// preserves neither the order asked for nor an entry per slug.
  Future<List<ContentCard>> cards(List<String> slugs) async {
    if (slugs.isEmpty) return const [];
    return _cards(await _post('/catalogue/cards', {'slugs': slugs}));
  }

  /// `GET /catalogue/persons` — the directory of actors and directors.
  Future<Paginated<Person>> persons({int? page}) async => Paginated.fromJson(
    await _get(_query('/catalogue/persons', {'page': page?.toString()})),
    Person.fromJson,
  );

  /// `GET /catalogue/content/{slug}` — one title in full.
  ///
  /// A series lists **every** season but fills in the episodes and players of
  /// one. Pass [season] to fill in a different one — the rest come back empty
  /// either way, and [Season.isLoaded] is what tells "not fetched yet" from
  /// "nothing to watch".
  ///
  /// Throws [ApiHttpException] with `isNotFound` for a slug nobody has.
  Future<ContentDetails> content(String slug, {int? season}) async =>
      ContentDetails.fromJson(
        await _get(
          _query('/catalogue/content/${Uri.encodeComponent(slug)}', {
            'season': season?.toString(),
          }),
        ),
      );

  // --- television ----------------------------------------------------------

  /// `GET /tv/channels` — every free channel, with its categories.
  ///
  /// Cached server-side, and each entry already says what is on right now, so a
  /// whole grid costs one request rather than one per row.
  Future<TvChannels> channels() async =>
      TvChannels.fromJson(await _get('/tv/channels'));

  /// `GET /tv/channels/{id}/schedule` — one channel's programmes for one day.
  ///
  /// A day nobody published comes back empty rather than as an error: a channel
  /// simply has no schedule that far out.
  Future<TvSchedule> schedule(int channelId, {DateTime? day}) async {
    final on = day == null ? '' : '?day=${_isoDay(day)}';
    return TvSchedule.fromJson(
      await _get('/tv/channels/$channelId/schedule$on'),
    );
  }

  /// `POST /tv/channels/{id}/stream` — a playable address.
  ///
  /// A lease, not an address: it carries a session and goes stale after
  /// [TvStream.refreshIn]. Ask again rather than storing it.
  ///
  /// [useProxy] is for browsers and only for browsers. The stitched playlist
  /// comes from a host that answers no `access-control-allow-origin`, so a page
  /// cannot read it; with the flag every address comes back pointing at
  /// `/stream`, which it can. A box should leave it off — the video then goes
  /// host to viewer instead of through us, which is faster and costs us
  /// nothing.
  Future<TvStream> stream(int channelId, {bool useProxy = false}) async =>
      TvStream.fromJson(
        await _send(
          'POST',
          _query('/tv/channels/$channelId/stream', {
            'use_proxy': useProxy ? 'true' : null,
          }),
        ),
      );

  /// `POST /playback/resolve` — a player page, read for the stream inside it.
  ///
  /// The catalogue hands out embed pages rather than streams, and on the web a
  /// page cannot read one: the host sends no CORS header, and it wants a
  /// `Referer` a browser is not allowed to set. The server has neither problem.
  ///
  /// [url] is one of the links already in a season's `playerData`. [season] and
  /// [episode] pick a leaf out of a serial's playlist; without them the first
  /// one wins, which is right for a film and wrong for episode nine.
  Future<List<PlaybackStream>> resolvePlayback(
    String url, {
    int? season,
    int? episode,
  }) async {
    final answer = await _post('/playback/resolve', {
      'url': url,
      'season': season,
      'episode': episode,
    });
    return answer.listOf('streams', PlaybackStream.fromJson);
  }

  /// The address of [url] as a browser is allowed to fetch it.
  ///
  /// `/stream` relays the playlist and its segments and rewrites the URLs
  /// inside an `.m3u8` so the nested requests come back through it too —
  /// without which a player reads the master through us and then fetches every
  /// segment straight from the origin, which is the request CORS blocks.
  ///
  /// Absolute, because a `<video>` is handed this and there is no page to
  /// resolve it against on every platform.
  String streamed(String url) =>
      uriFor('/stream?url=${Uri.encodeQueryComponent(url)}').toString();

  /// Closes the underlying [Transport]. Skip it when the transport is shared —
  /// closing is the owner's job.
  void close() => _transport.close();

  // --- plumbing ------------------------------------------------------------

  Identity _remember(Identity identity) {
    final issued = identity.session.token;
    if (issued != null) token = issued;
    return identity;
  }

  List<ContentCard> _cards(JsonMap json) =>
      json.listOf('items', ContentCard.fromJson);

  /// A path with the entries that are not null appended. A list value repeats
  /// the key, which is what FastAPI reads back as a list.
  static String _query(String path, Map<String, Object?> params) {
    final parts = <String>[];
    for (final entry in params.entries) {
      switch (entry.value) {
        case final String value:
          parts.add('${entry.key}=${Uri.encodeQueryComponent(value)}');
        case final List<String> values:
          for (final value in values) {
            parts.add('${entry.key}=${Uri.encodeQueryComponent(value)}');
          }
        case _:
          break;
      }
    }
    return parts.isEmpty ? path : '$path?${parts.join('&')}';
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// An address the API handed back as a path, made absolute.
  ///
  /// The server does not know what address it is reached on, so anything it
  /// serves itself comes back as a path rather than a URL — a proxied image, a
  /// pairing page. This resolves one against the base this client already
  /// calls, and leaves anything already absolute alone.
  ///
  /// Images are the reason it exists. The catalogue's own host sends no
  /// `access-control-allow-origin`, so a browser fetches a poster and then
  /// cannot paint it: the pixels taint the canvas and a tainted canvas is not
  /// a texture. Those come back as `/proxy/…` and go through the API instead.
  String resolve(String url) =>
      url.startsWith('/') ? uriFor(url).toString() : url;

  Uri uriFor(String path) {
    final base = baseUrl.toString().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<JsonMap> _get(String path) => _send('GET', path);

  Future<JsonMap> _post(String path, JsonMap body) =>
      _send('POST', path, body: body);

  Future<JsonMap> _send(String method, String path, {JsonMap? body}) async {
    final uri = uriFor(path);
    final headers = {
      ..._headers,
      if (_token != null) 'Authorization': 'Bearer $_token',
      if (body != null) 'Content-Type': 'application/json',
    };

    final ApiResponse response;
    try {
      response = await _transport
          .send(
            ApiRequest(
              method: method,
              url: uri,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            ),
          )
          .timeout(timeout);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiNetworkException(uri, error);
    }

    return decodeObject(response, uri);
  }
}
