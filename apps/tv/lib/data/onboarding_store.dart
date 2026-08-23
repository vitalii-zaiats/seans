import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the box is signed in.
enum AccountMode {
  /// Nothing is kept anywhere but this box.
  anonymous,

  /// A local identity that a real account can be claimed onto later.
  guest,

  /// Paired with an account.
  linked;

  static AccountMode fromName(String? name) => values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => AccountMode.anonymous,
  );
}

/// What the owner agreed to, if anything.
enum SupportChoice {
  none,

  /// A one-off payment.
  donation,

  /// Sharing the connection. Requires [OnboardingState.bandwidthConsent] on
  /// top of this — the choice and the informed consent are separate on
  /// purpose.
  bandwidth;

  static SupportChoice fromName(String? name) => values.firstWhere(
    (choice) => choice.name == name,
    orElse: () => SupportChoice.none,
  );
}

class OnboardingState {
  const OnboardingState({
    this.completed = false,
    this.account = AccountMode.anonymous,
    this.support = SupportChoice.none,
    this.bandwidthConsent = false,
  });

  /// Whether first-run has been through to the end.
  final bool completed;

  final AccountMode account;
  final SupportChoice support;

  /// Explicit, separately-given agreement to share the connection.
  ///
  /// Kept apart from `support == bandwidth` so the flag can never be set by
  /// picking an option on a list — it takes its own screen, and revoking it
  /// leaves the rest of the answers alone.
  final bool bandwidthConsent;

  /// Sharing is only ever on when both halves agree.
  bool get isSharingBandwidth =>
      support == SupportChoice.bandwidth && bandwidthConsent;

  OnboardingState copyWith({
    bool? completed,
    AccountMode? account,
    SupportChoice? support,
    bool? bandwidthConsent,
  }) => OnboardingState(
    completed: completed ?? this.completed,
    account: account ?? this.account,
    support: support ?? this.support,
    bandwidthConsent: bandwidthConsent ?? this.bandwidthConsent,
  );
}

/// Remembers what first-run settled, so it only ever runs once.
///
/// The change signal lives on [completedListenable] rather than on the store
/// itself, because `RepositoryProvider` — which hands this around — refuses a
/// `Listenable` outright.
class OnboardingStore {
  OnboardingStore(this._prefs)
    : _completedNotifier = ValueNotifier(_prefs.getBool(_completed) ?? false);

  static const _completed = 'onboarding.completed';
  static const _account = 'onboarding.account';
  static const _support = 'onboarding.support';
  static const _consent = 'onboarding.bandwidthConsent';

  static Future<OnboardingStore> open() async =>
      OnboardingStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final ValueNotifier<bool> _completedNotifier;

  /// Fires when first run finishes, and when it is reset from settings — which
  /// is what puts the box back into setup without a restart.
  ValueListenable<bool> get completedListenable => _completedNotifier;

  void dispose() => _completedNotifier.dispose();

  OnboardingState read() => OnboardingState(
    completed: _prefs.getBool(_completed) ?? false,
    account: AccountMode.fromName(_prefs.getString(_account)),
    support: SupportChoice.fromName(_prefs.getString(_support)),
    bandwidthConsent: _prefs.getBool(_consent) ?? false,
  );

  Future<void> save(OnboardingState state) async {
    _completedNotifier.value = state.completed;
    await _prefs.setBool(_completed, state.completed);
    await _prefs.setString(_account, state.account.name);
    await _prefs.setString(_support, state.support.name);
    await _prefs.setBool(_consent, state.bandwidthConsent);
  }

  /// Puts the box back to a first boot. Offered in settings, because an
  /// agreement somebody cannot withdraw is not much of an agreement.
  Future<void> reset() async {
    await save(const OnboardingState());
  }
}
