import '../exceptions.dart';
import '../json.dart';
import 'account.dart';
import 'update.dart';

/// This installation, as the server has it.
final class Install {
  const Install({
    required this.id,
    required this.isFirstRun,
    required this.registeredAt,
  });

  factory Install.fromJson(JsonMap json) => Install(
    id: json.requireString('id', owner: 'Install'),
    isFirstRun: json.boolOr('first_run'),
    registeredAt: json.requireDateTime('registered_at', owner: 'Install'),
  );

  /// The uuid the app sent — echoed back, so the two can be compared.
  final String id;

  /// True only on the very first start. A reinstall generates a new id, so this
  /// is "the app has never run here", not "the person is new".
  final bool isFirstRun;

  final DateTime registeredAt;

  @override
  String toString() => 'Install($id${isFirstRun ? ', first run' : ''})';
}

/// Everything the server says when the app starts.
///
/// [install], [account] and [session] are all `null` for a [Launch.anonymous] —
/// the box told the server nothing it could remember, so there is nothing to
/// hand back. [update], [features] and [serverTime] always arrive: declining an
/// account is not declining to hear that the app is too old.
final class Start {
  const Start({
    required this.update,
    required this.features,
    required this.serverTime,
    this.install,
    this.account,
    this.session,
  });

  factory Start.fromJson(JsonMap json) {
    const owner = 'Start';
    final install = json.mapOrNull('install');
    final account = json.mapOrNull('account');
    final session = json.mapOrNull('session');
    final update = json.mapOrNull('update');
    if (update == null) {
      throw ApiSerializationException(
        'expected an `update` object on a $owner',
      );
    }
    return Start(
      update: UpdatePlan.fromJson(update),
      features: json.boolMap('features'),
      serverTime: json.requireDateTime('server_time', owner: owner),
      install: install == null ? null : Install.fromJson(install),
      account: account == null ? null : Account.fromJson(account),
      session: session == null ? null : Session.fromJson(session),
    );
  }

  final Install? install;
  final Account? account;
  final Session? session;

  final UpdatePlan update;

  /// Switches this build may see. Ask through [feature] rather than indexing:
  /// a flag the server has not heard of is off, not missing.
  final Map<String, bool> features;

  /// What time it is where the decisions are made. Use it rather than the
  /// device clock for anything with a deadline — a television that has been
  /// unplugged for a month often believes it is 1970.
  final DateTime serverTime;

  /// Which of the three the box ended up in.
  AccountMode get mode => account?.mode ?? AccountMode.anonymous;

  /// Whether the server knows this installation at all.
  bool get isAnonymous => install == null;

  /// Whether [name] is switched on for this build. Unknown flags are off.
  bool feature(String name) => features[name] ?? false;

  @override
  String toString() => 'Start(${mode.name}, ${update.action.wire})';
}
