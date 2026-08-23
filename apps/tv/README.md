# seans_tv

Сеанс — the home screen of an Android TV box, and the movie app it is made of.

Flutter, one pub workspace with `packages/dart/*`, talking to `apps/api` over
REST (`contracts/openapi.json`). It replaces the launcher: the catalogue, live
channels, the box's own apps and drives, and a remote a phone can drive.

```bash
flutter run -d <device>              # a box, or a desktop window
flutter build apk --release
flutter build web --release          # what `apps/tv/Dockerfile` packages
dart analyze lib && dart format lib
```

## Two names that are not the same thing

- **Сеанс / `seans_tv`** is this app.
- **kinostrain** is somebody else's: the catalogue upstream, and the client
  package that reads it (`packages/python/kinostrain`, `KinostrainApi`,
  `kinostrain.com` in a `Referer`). Those keep the name because they *are* that
  service — renaming them would be a lie about which host is being called.

The Android `applicationId` is the one place the old name survives in this app,
and `android/app/build.gradle.kts` says why: to Android that string is the
app's identity, so changing it installs a second app rather than renaming this
one.

## Where the web build fits

`flutter build web` produces the PWA that `apps/web`'s downloads page points at
— the same program in a browser tab. It needs the API on its own origin, which
is what `nginx.conf.template` arranges: kinostrain.com sends no CORS header a
browser will accept, so everything goes through our API instead.
