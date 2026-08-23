# super_movies_api

Typed Dart client for the [Super Movies API](../../../apps/api).

## The one call every app makes

```dart
final api = SuperMoviesApi(
  baseUrl: Uri.parse('https://api.supermovies.example'),
  token: await storage.readToken(),        // whatever last time handed back
  onToken: storage.writeToken,             // persist rotations for me
);

final start = await api.start(Launch.identified(
  installId: installId,                    // generated once, kept in storage
  platform: AppPlatform.android,
  vendor: installerPackage,                // null unless android
  version: packageInfo.version,
));

if (start.update.isRequired) return UpdateWall(start.update);
```

What comes back: the install, the account, the session, the update plan, the
feature flags, and the server's clock.

## The three modes

They are the three choices the first-run screen offers, and the client makes the
difference structural rather than a flag you can forget:

| First-run choice | Call | What the server keeps |
|---|---|---|
| Continue anonymously | `Launch.anonymous(...)` | nothing — no install row, no account, no session |
| Continue as a guest | `Launch.identified(...)` | an install and a nameless account, reached by a token |
| Create an account | `Launch.identified(...)` then `claim(...)` | the same account, with an email on it |

`start.mode` tells you which one you are in. Anonymous still gets the update
plan and the feature flags: declining an account is not declining to hear that
the app is too old.

## The token looks after itself

Every call that creates or rotates a session stores it on the client and sends
it afterwards. That matters most for `claim`, which rotates deliberately — the
old token is revoked the moment the account gains a password, so a client that
kept it by hand would sign itself out at exactly the wrong moment.

## Updates

`update.channel` is not a preference, it is a consequence of who installed the
app:

- `store` — Google installed it, so send the user to the listing. A build that
  sideloads its own APK gets pulled from the shop.
- `self` — an APK from our own site, an `.exe`, a `.deb`. Download `update.url`.
- `auto` — the web build. A reload *is* the new version.

The same split decides features: a Play Store build gets fewer of them switched
on, and `start.feature(name)` answers `false` for anything the server did not
mention.

## Transport

The package performs no I/O itself: it talks to a `Transport`, and
`HttpTransport` is the one it builds when you supply nothing. Bring your own to
add retries, logging or a test double — an implementation is two methods, and it
has two rules: do **not** throw on a non-2xx status, and do throw on socket, DNS
or TLS failures.
