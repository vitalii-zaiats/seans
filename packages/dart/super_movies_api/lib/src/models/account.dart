import '../exceptions.dart';
import '../json.dart';

/// Which of the three the box settled on.
///
/// The same three choices the first-run screen offers, named the same way, so
/// the answer a person gave and the state the client is in are one value rather
/// than two that can disagree.
enum AccountMode {
  /// Nothing is kept anywhere but this box. No install row, no session.
  anonymous,

  /// A server-side account with no name on it, reached by a token. History
  /// survives a restart and can have a real account claimed onto it later.
  guest,

  /// The same row, with an email and a password on it.
  claimed,
}

/// Whoever the session belongs to.
final class Account {
  const Account({
    required this.id,
    required this.displayName,
    required this.isGuest,
    required this.isAdmin,
    this.email,
  });

  factory Account.fromJson(JsonMap json) {
    const owner = 'Account';
    return Account(
      id: json.requireString('id', owner: owner),
      displayName: json.requireString('display_name', owner: owner),
      isGuest: json.boolOr('is_guest', fallback: true),
      isAdmin: json.boolOr('is_admin'),
      email: json.stringOrNull('email'),
    );
  }

  /// Opaque and stable. Not the database id — the outside world never sees one.
  final String id;

  final String displayName;

  /// `null` until the account is claimed.
  final String? email;

  final bool isGuest;
  final bool isAdmin;

  AccountMode get mode => isGuest ? AccountMode.guest : AccountMode.claimed;

  @override
  String toString() => 'Account($id, ${isGuest ? 'guest' : email})';
}

/// A live session.
final class Session {
  const Session({required this.expiresAt, this.token});

  factory Session.fromJson(JsonMap json) => Session(
    expiresAt: json.requireDateTime('expires_at', owner: 'Session'),
    token: json.stringOrNull('token'),
  );

  /// The bearer token, and `null` when the one you sent still works — the
  /// server never repeats a token you already stored back at you.
  ///
  /// [SuperMoviesApi] keeps this for you; you only need it to persist it.
  final String? token;

  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  @override
  String toString() => 'Session(until $expiresAt)';
}

/// An account together with the session that proves it.
///
/// Returned by everything that creates a session: becoming a guest, claiming,
/// registering, signing in.
final class Identity {
  const Identity({required this.session, required this.account});

  factory Identity.fromJson(JsonMap json) {
    const owner = 'Identity';
    final session = json.mapOrNull('session');
    final account = json.mapOrNull('account');
    if (session == null || account == null) {
      throw ApiSerializationException(
        'expected `session` and `account` objects on an $owner',
      );
    }
    return Identity(
      session: Session.fromJson(session),
      account: Account.fromJson(account),
    );
  }

  final Session session;
  final Account account;

  @override
  String toString() => 'Identity(${account.id})';
}
