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

  /// Ask for a code, put it on screen, and wait.
  Future<void> start() async {
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
}
