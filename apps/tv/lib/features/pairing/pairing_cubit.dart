import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../../core/sfx.dart';
import '../../data/startup.dart';
import 'device_name.dart';
import 'pairing_state.dart';

/// Asking a phone to sign this box in.
///
/// A cubit of its own rather than part of the wizard, because two screens want
/// it: first run offers pairing as one of three ways to have an account, and
/// the account screen offers it later to a guest who has changed their mind.
/// The dance is the same both times, and two copies of a polling loop is two
/// copies to keep in step.
///
/// **The secret never leaves this box.** Approving on the phone says only "yes,
/// as me"; collecting the session is this side's own step, with something the
/// phone was never shown. So a code somebody was talked into approving still
/// hands the account to the television that asked for it, and to nothing else.
class PairingCubit extends Cubit<PairingState> {
  PairingCubit(this._api, this._startup) : super(const PairingState());

  final SuperMoviesApi _api;
  final Startup _startup;

  /// Completed to stop the poll that is running, if one is.
  ///
  /// One per run rather than one per cubit: a code can be asked for again —
  /// "показати новий код" on the account screen does exactly that — and a
  /// single completer, once used, would stop every later poll the moment it
  /// started.
  ///
  /// `isClosed` alone does not do this job. It silences the *emit*; the loop
  /// underneath carries on asking. A pairing screen opened in a browser and
  /// left behind went on polling `/auth/device/collect` every two seconds
  /// until the code expired, for a code nobody was going to approve.
  Completer<void>? _polling;

  /// Stop asking. Safe to call when nothing is running, and twice.
  ///
  /// Public because leaving the screen is not the only way to abandon a
  /// pairing: the wizard offers "continue as a guest" right beside the code,
  /// and that walks on while this cubit stays alive underneath.
  void stop() {
    final polling = _polling;
    _polling = null;
    if (polling != null && !polling.isCompleted) polling.complete();
  }

  /// Ask for a code, put it on screen, and wait.
  Future<void> start() async {
    // Whatever was being asked for is superseded by what is about to be.
    stop();
    final gone = _polling = Completer<void>();

    emit(const PairingState(status: PairingStatus.asking));

    final DeviceLink link;
    try {
      link = await _api.startDeviceLink(deviceName: describeThisDevice());
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(PairingState(status: PairingStatus.failed, error: error.message));
      return;
    }

    if (isClosed) return;
    emit(PairingState(status: PairingStatus.waiting, link: link));

    // Polled rather than pushed, and deliberately: the two devices may have
    // nothing between them but this API, and a poll works wherever a request
    // does. The code's own lifetime is the timeout — there is nothing left to
    // wait for once it has gone stale.
    try {
      final identity = await _api.awaitDeviceLink(
        link.secret,
        timeout: Duration(seconds: link.expiresIn),
        until: gone.future,
      );
      if (isClosed) return;

      if (identity == null) {
        emit(state.copyWith(status: PairingStatus.expired));
        return;
      }

      // The client swapped to the collected token on its way through, so this
      // box is already that account. Announcing again is what tells the rest of
      // the app who it is now — the tab row, the sections, the settings screen.
      await _startup.announce(remembered: true);
      if (isClosed) return;

      // Here rather than in a listener on the screen: this cubit exists because
      // *two* screens run the same dance — first run, and the account screen
      // later — and a sound wired into both is the second copy this class was
      // written to avoid. `Sfx` takes no context and returns nothing, so the
      // coupling is one import rather than a view creeping into a cubit.
      SfxCue.paired.play();

      emit(
        PairingState(
          status: PairingStatus.linked,
          link: link,
          account: identity.account,
        ),
      );
    } on ApiException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(status: PairingStatus.failed, error: error.message));
    }
  }

  @override
  Future<void> close() {
    stop();
    return super.close();
  }
}
