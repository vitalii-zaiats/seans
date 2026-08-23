import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/iptv.dart';
import 'package:provider/provider.dart';
import 'package:super_movies_api/super_movies_api.dart';

import 'core/router.dart';
import 'platform/box_for_platform.dart';
import 'data/camera_store.dart';
import 'data/doh_network.dart';
import 'data/install_store.dart';
import 'data/iptv_store.dart';
import 'data/library_store.dart';
import 'data/network_probe.dart';
import 'data/onboarding_store.dart';
import 'data/pinned_apps_store.dart';
import 'data/playlist_store.dart';
import 'data/settings_store.dart';
import 'data/startup.dart';
import 'data/steam_store.dart';
import 'data/stream_resolver.dart';
import 'data/sweet_tv_store.dart';
import 'data/web_proxy.dart';
import 'features/onboarding/onboarding_cubit.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'parts/parts.dart';
import 'theme/nocturne.dart';

/// Owns everything that outlives a screen and hands it to the tree.
///
/// One client where there used to be three. The catalogue and the free channels
/// are our own API's now, which is what makes a browser build possible at all:
/// neither service sends a CORS header a browser will accept, and no amount of
/// arranging on this side changes that.
///
/// What is still built here is what is genuinely the app's: a playlist loader
/// with a cache, a name resolver, a probe. What belongs to the machine — an APK
/// downloader, a scanner for the local network — is built by [Parts], and only
/// on the platform that has one.
/// What the arrow keys mean.
///
/// Flutter binds them differently on the web: `WidgetsApp.defaultShortcuts`
/// hands back a map where the arrows are `ScrollIntent`, because on a web page
/// arrows scroll and Tab moves focus. Everywhere else they are
/// `DirectionalFocusIntent`.
///
/// That default is right for a document and wrong for this. The interface is a
/// television one wherever it runs, driven by a D-pad — and in a browser the
/// arrows did nothing at all, because a screen that fits has nothing to
/// scroll. So the four go back to moving focus, and the rest of the web map —
/// Tab, Enter, Escape, page up and down — is kept as it comes.
Map<ShortcutActivator, Intent>? get _shortcuts {
  if (!kIsWeb) return null;
  return <ShortcutActivator, Intent>{
    ...WidgetsApp.defaultShortcuts,
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const DirectionalFocusIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const DirectionalFocusIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const DirectionalFocusIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const DirectionalFocusIntent(TraversalDirection.right),
  };
}

class LauncherApp extends StatefulWidget {
  const LauncherApp({
    required this.api,
    required this.remoteBase,
    required this.parts,
    required this.startup,
    required this.library,
    required this.settings,
    required this.onboarding,
    required this.playlists,
    required this.iptv,
    required this.sweet,
    required this.steam,
    required this.cameras,
    required this.pinnedApps,
    required this.installs,
    super.key,
  });

  final SuperMoviesApi api;

  /// Where the page a QR code opens lives. Handed down rather than looked up:
  /// it is a fact about this deployment, and the screen that draws the code
  /// should not have to know where a build-time constant is kept.
  final Uri remoteBase;

  final Parts parts;
  final Startup startup;
  final LibraryStore library;
  final SettingsStore settings;
  final OnboardingStore onboarding;
  final PlaylistStore playlists;
  final IptvStore iptv;
  final SweetTvStore sweet;
  final SteamStore steam;
  final CameraStore cameras;
  final PinnedAppsStore pinnedApps;
  final InstallStore installs;

  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> {
  /// Names looked up over HTTPS, when the owner leaves that on.
  ///
  /// Built once and shared: the resolver's cache is the point, and one per
  /// client would ask again for every host on every screen.
  late final DohNetwork _doh = DohNetwork();

  /// The ashdi player page, which is the request that fails first on a network
  /// that interferes with anything.
  late final StreamResolver _streams = StreamResolver(
    client: WebProxy.wrap(
      widget.settings.value.useDoh ? _doh.client() : http.Client(),
    ),
    // Only the web build uses it, and only because a browser may not read a
    // player page itself. The box keeps reading them directly.
    api: widget.api,
  );

  late final NetworkProbe _probe = NetworkProbe(api: widget.api);

  late final http.Client _http = WebProxy.wrap(http.Client());

  /// Built once. A router rebuilt on every settings change would throw the
  /// history away with it — and the theme changes on every colour picked.
  ///
  /// The wizard is a route like any other, reached by a redirect that listens
  /// to the same store: "set up again" in settings puts the box back into the
  /// flow without a restart.
  late final GoRouter _router = buildRouter(
    onboarding: widget.onboarding,
    parts: widget.parts,
    welcome: (context) => BlocProvider(
      create: (context) => OnboardingCubit(
        widget.onboarding,
        widget.startup,
        _probe,
        widget.settings,
        widget.sweet,
        widget.iptv,
        widget.steam,
      ),
      child: const OnboardingScreen(),
    ),
  );

  /// Playlists already fetched this session, with the time they arrived.
  ///
  /// The home row and the ТБ screen ask for the same lists, and a channel list
  /// is a few hundred kilobytes that changes maybe weekly — refetching it on
  /// every glance at the home screen would be the slowest thing the launcher
  /// does. Only successes land here, so a failed list is retried.
  final _playlistCache = <Uri, (DateTime, String)>{};

  static const _playlistFreshFor = Duration(minutes: 30);

  late final IptvLoader _iptvLoader = IptvLoader(
    fetch: (url) async {
      if (_playlistCache[url] case (final at, final body)
          when DateTime.now().difference(at) < _playlistFreshFor) {
        return body;
      }

      final response = await _http
          .get(url)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw IptvException('список відповів ${response.statusCode}', url: url);
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      _playlistCache[url] = (DateTime.now(), body);
      return body;
    },
  );

  @override
  void dispose() {
    _doh.close();
    _streams.close();
    _probe.close();
    _http.close();
    widget.api.close();
    widget.parts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SuperMoviesApi>.value(value: widget.api),
        RepositoryProvider<Parts>.value(value: widget.parts),
        RepositoryProvider<Uri>.value(value: widget.remoteBase),
        // What this launch is allowed to be. Read by the tab row and by the
        // sections that check before they offer themselves.
        ChangeNotifierProvider<Startup>.value(value: widget.startup),
        RepositoryProvider<LibraryStore>.value(value: widget.library),
        RepositoryProvider<StreamResolver>.value(value: _streams),
        RepositoryProvider<SettingsStore>.value(value: widget.settings),
        RepositoryProvider<OnboardingStore>.value(value: widget.onboarding),
        RepositoryProvider<PlaylistStore>.value(value: widget.playlists),
        RepositoryProvider<IptvStore>.value(value: widget.iptv),
        RepositoryProvider<SweetTvStore>.value(value: widget.sweet),
        RepositoryProvider<SteamStore>.value(value: widget.steam),
        RepositoryProvider<CameraStore>.value(value: widget.cameras),
        RepositoryProvider<PinnedAppsStore>.value(value: widget.pinnedApps),
        RepositoryProvider<InstallStore>.value(value: widget.installs),
        // The playlist package makes no requests of its own; this is the one
        // place a network stack is handed to it.
        RepositoryProvider<IptvLoader>.value(value: _iptvLoader),
        // No endpoint for curated collections yet. Swapping this one binding
        // for a real implementation is the whole of that work on this side.
        RepositoryProvider<PublicPlaylists>.value(
          value: PublicPlaylists.unavailable,
        ),
        // Whatever only this machine can offer.
        ...widget.parts.providers(),
      ],
      // The theme is built from the settings, so listening to them here is what
      // repaints the whole interface when a colour is picked.
      child: ValueListenableBuilder<Settings>(
        valueListenable: widget.settings.listenable,
        builder: (context, settings, _) => MaterialApp.router(
          routerConfig: _router,
          shortcuts: _shortcuts,
          title: 'Сеанс',
          debugShowCheckedModeBanner: false,
          theme: Nocturne.themeFor(
            accent: Nocturne.accentById(settings.accentId),
            ground: Nocturne.groundById(settings.groundId),
            focusGlow: settings.focusGlow,
            uiScale: settings.uiScale,
            // The stored answer only decides where a pointer is *optional* —
            // on a box, where "on" means somebody has an air mouse. Anywhere
            // else there is always a cursor, and honouring a stored "off"
            // would drop the mouse handlers off every tile and leave the
            // interface unclickable, with the control that would turn it back
            // on now hidden for the very same reason. See `settings_screen`.
            pointer: platformBox.present ? settings.pointer : true,
          ),
          locale: const Locale('uk'),
          supportedLocales: const [Locale('uk'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
  }
}
