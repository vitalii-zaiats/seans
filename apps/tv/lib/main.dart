import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:super_movies_api/super_movies_api.dart' hide AccountMode;

import 'app.dart';
import 'data/camera_store.dart';
import 'data/install_store.dart';
import 'data/iptv_store.dart';
import 'data/library_store.dart';
import 'data/onboarding_store.dart';
import 'data/pinned_apps_store.dart';
import 'data/playlist_store.dart';
import 'data/settings_store.dart';
import 'data/startup.dart';
import 'data/steam_store.dart';
import 'data/sweet_tv_store.dart';
import 'core/remote/activity.dart';
import 'parts/parts_for_platform.dart';
import 'platform/install_offer.dart';
import 'platform/install_prompt_for_platform.dart';

/// Where the API lives.
///
/// A compile-time constant so a build can be pointed at a deployment without a
/// settings screen: `flutter build web --dart-define=API=https://api.example`.
const apiBase = String.fromEnvironment(
  'API',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Where the page a QR code opens is served from — `apps/remote`.
///
/// Separate from [apiBase] because it is a different thing in production: the
/// API is something the box talks to, and this is an address a person reads off
/// a screen and points a camera at. The server hands back a path and refuses to
/// guess the host, for the good reason that it cannot know one.
const remoteBase = String.fromEnvironment(
  'REMOTE',
  defaultValue: 'http://127.0.0.1:5174',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A launcher owns the whole panel; there are no system bars over a home
  // screen, and nothing here rotates.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
  ]);

  // Read before the first frame: the home screen's "Continue watching" rail is
  // part of that frame, and a launcher that redraws itself a moment after it
  // appears looks broken.
  final library = await LibraryStore.open();
  final settings = await SettingsStore.open();
  final onboarding = await OnboardingStore.open();
  final playlists = await PlaylistStore.open();
  final iptv = await IptvStore.open();
  final sweet = await SweetTvStore.open();
  final steam = await SteamStore.open();
  final cameras = await CameraStore.open();
  final pinnedApps = await PinnedAppsStore.open();
  final installs = await InstallStore.open();

  final parts = partsForPlatform();
  final api = SuperMoviesApi(baseUrl: Uri.parse(apiBase));

  // Before the first frame, and that is the whole point: a browser fires
  // `beforeinstallprompt` moments after the page loads and never fires it
  // again, so anything that waited for the screen that draws the offer would
  // be listening for an event that had already gone. Off the web this is a
  // constant that answers "no" — see `platform/install_prompt.dart`.
  installPrompt = installPromptForPlatform();

  // Watches every key press: the focus ring waits for the first arrow, and
  // the idle screen has to know somebody is there even while a player is
  // answering the presses itself — see `core/remote/activity.dart`.
  RemoteActivity.watch();

  // Announced before the first frame too, and for the same reason: the answer
  // says which sections this build may show, and a row that loses two tabs a
  // second after it is drawn looks broken in exactly the same way.
  //
  // The vendor is who installed this copy — `com.android.vending` for Play,
  // which is the one that matters, and null everywhere a browser runs.
  final startup = Startup(
    api: api,
    installs: installs,
    version: (await PackageInfo.fromPlatform()).version,
    // Who installed this copy. `com.android.vending` is the one that matters —
    // it decides where an update comes from and which sections this build may
    // show at all — and it is null wherever there is no installer to ask.
    vendor: await parts.box.installer(),
  );

  // A box that has been set up announces itself before the first frame, because
  // the answer decides which tabs exist and a row that loses two of them a
  // second later looks broken.
  //
  // A box on its first ever start does not: the first thing the wizard asks is
  // whether to be remembered at all, and until that is answered there is
  // nothing honest to send. `OnboardingCubit` announces the moment it is.
  final chosen = onboarding.read();
  if (chosen.completed) {
    await startup.announce(remembered: chosen.account != AccountMode.anonymous);
  }

  runApp(
    LauncherApp(
      api: api,
      remoteBase: Uri.parse(remoteBase),
      parts: parts,
      startup: startup,
      library: library,
      settings: settings,
      onboarding: onboarding,
      playlists: playlists,
      iptv: iptv,
      sweet: sweet,
      steam: steam,
      cameras: cameras,
      pinnedApps: pinnedApps,
      installs: installs,
    ),
  );
}
