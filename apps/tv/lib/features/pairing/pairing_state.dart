import 'package:equatable/equatable.dart';
import 'package:super_movies_api/super_movies_api.dart';

/// Where the pairing dance stands.
enum PairingStatus {
  /// Nothing asked for yet.
  idle,

  /// Waiting for the server to hand over a code.
  asking,

  /// The code is on screen and nobody has approved it.
  waiting,

  /// Somebody did, and this box now has an account.
  linked,

  /// The code ran out with nobody approving it.
  expired,

  /// Something else went wrong, and [PairingState.error] says what.
  failed,
}

/// The pairing, as the screen needs to draw it.
class PairingState extends Equatable {
  const PairingState({
    this.status = PairingStatus.idle,
    this.link,
    this.account,
    this.error,
  });

  final PairingStatus status;

  /// The code, the address for the QR, and the secret that never leaves here.
  final DeviceLink? link;

  /// Whoever the box ended up as. Only once [status] is `linked`.
  final Account? account;

  final String? error;

  bool get isWaiting => status == PairingStatus.waiting;
  bool get isLinked => status == PairingStatus.linked;

  /// Whether the screen should offer to ask again rather than to keep waiting.
  bool get canRetry =>
      status == PairingStatus.expired || status == PairingStatus.failed;

  PairingState copyWith({
    PairingStatus? status,
    DeviceLink? link,
    Account? account,
    String? error,
  }) => PairingState(
    status: status ?? this.status,
    link: link ?? this.link,
    account: account ?? this.account,
    error: error,
  );

  @override
  List<Object?> get props => [status, link?.code, account?.id, error];
}
