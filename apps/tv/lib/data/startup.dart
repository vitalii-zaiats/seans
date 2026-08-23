import 'package:flutter/foundation.dart';
import 'package:super_movies_api/super_movies_api.dart';

import 'install_store.dart';

/// What the server was told about this launch, and what it said back.
///
/// Held for the life of the process. Everything in it is a fact about *this*
/// start: which sections this build may show, whether it is too old, and who
/// the box ended up signed in as.
///
/// **Announced after the question, not before it.** The first thing first run
/// asks is whether to be remembered at all, and until somebody answers there is
/// nothing honest to send: an id would be a promise nobody made, and no id
/// would be a refusal nobody gave. So a box that has been set up announces
/// itself before the first frame, and a box on its first ever start announces
/// itself the moment the answer exists — which is why this is a `ChangeNotifier`
/// rather than a value handed down once.
///
/// [announce] is deliberately forgiving. A launcher that refused to open
/// because an API was unreachable could not show a locally stored playlist on a
/// box with no internet — so a failure leaves [answer] null and every section
/// switched on, and the parts that need the network fail on their own screens,
/// where there is somewhere to say so.
class Startup extends ChangeNotifier {
  Startup({
    required SuperMoviesApi api,
    required InstallStore installs,
    required String version,
    String? vendor,
  }) : _api = api,
       _installs = installs,
       _version = version,
       _vendor = vendor;

  final SuperMoviesApi _api;
  final InstallStore _installs;
  final String _version;

  /// Who installed this copy — `com.android.vending` for Play, and null
  /// wherever there is no installer to ask, which includes every browser.
  final String? _vendor;

  Start? _answer;
  Object? _failure;
  bool _announced = false;

  /// What came back, or `null` when nothing has been announced yet or the
  /// server could not be reached.
  Start? get answer => _answer;

  /// Why not, for a settings screen that wants to say.
  Object? get failure => _failure;

  /// Whether this launch has been announced at all, however it went.
  bool get announced => _announced;

  bool get reached => _answer != null;

  /// Whether a section may be shown.
  ///
  /// A name the server did not mention is on. That is what makes adding a
  /// section a change in this app rather than a deploy on the other side — and
  /// it is why the flags are named after `NavTab` ids and nothing else.
  bool allows(String section) => _answer?.features[section] ?? true;

  /// What to do about the version this build is.
  UpdatePlan? get update => _answer?.update;

  /// The account the box ended up with, if it asked for one.
  Account? get account => _answer?.account;

  /// Tell the server this launch happened.
  ///
  /// [remembered] is the answer to the only question that matters here. False
  /// sends no install id at all, and the server keeps its side of that: no
  /// install row, no account, no session — just the update plan and the flags,
  /// which are facts about the build rather than about the person.
  Future<void> announce({required bool remembered}) async {
    final id = remembered ? await _installs.ensure() : _installs.id;
    final launch = id == null
        ? Launch.anonymous(
            platform: currentPlatform,
            version: _version,
            vendor: _vendor,
          )
        : Launch.identified(
            installId: id,
            platform: currentPlatform,
            version: _version,
            vendor: _vendor,
          );

    try {
      _answer = await _api.start(launch);
      _failure = null;
    } on ApiException catch (error) {
      _answer = null;
      _failure = error;
    }
    _announced = true;
    notifyListeners();
  }

  /// Stop being remembered, here and on the server.
  ///
  /// The way back from a guest to nothing at all: the account and its sessions
  /// are deleted, the id is dropped, and the next start announces nothing.
  Future<void> forget() async {
    if (_api.isSignedIn) {
      try {
        await _api.forget();
      } on ApiException {
        // A server that cannot be reached must not trap somebody in an account
        // they asked to leave. The local half is what this box acts on.
      }
    }
    await _installs.forget();
    _answer = null;
    notifyListeners();
  }
}

/// Which of the four this build is.
///
/// `defaultTargetPlatform` rather than `dart:io`: reading `Platform` at all has
/// to be guarded on the web, where that library compiles to a stub whose members
/// throw the moment they are touched.
AppPlatform get currentPlatform {
  if (kIsWeb) return AppPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.windows => AppPlatform.windows,
    _ => AppPlatform.linux,
  };
}
