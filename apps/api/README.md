# api

Super Movies API. FastAPI over SQLAlchemy over Postgres, arranged so a second
transport (gRPC) can be added without touching a single decision.

## Layout

```
src/api/
  settings.py   configuration, prefix API_
  errors.py     domain errors — a service raises, a transport translates
  versions.py   which routers answer under which prefix
  main.py       FastAPI: middleware, routers, error → status code
  core/         engine, Base, Repository, security, composition root
  modules/      one folder per feature
    installs/   POST /api/v1/init — the first call an app makes
    accounts/   guests, claims, logins, tokens, and pairing a television
    release/    what to update, what to switch on
    remote/     driving a box from a phone
    tv/         free-to-air channels from sweet.tv
migrations/     alembic, async, URL from api.settings
```

**MVC, vertically.** `models.py` + `repository.py` are the model, `schemas.py`
is the view, `service.py` is the controller. `router.py` is not a controller —
it reads a request, calls one service method and renders the result. Anything it
decided would be a decision gRPC could not reach.

**A module never imports another module.** What it needs from outside it states
itself, in its own `ports.py`, as a `Protocol` over `Literal`s; the provider
satisfies it structurally without ever having heard of it. `deps.py` (HTTP) and
`core/services.py` (everything else) are the only files allowed to know which
service satisfies which port.

There is exactly one `adapters.py`, in `remote/`, and it is there for the reason
the rule allows one: "which boxes may this person drive" is half an accounts
question and half an installs question, so something has to have met both.

## Versions

**Every path in this document is under `/api/v1`.** The JSON API is versioned
and moves as one: `POST /api/v1/init`, `GET /api/v1/catalogue/search`. A client
does not choose the version — the version is what it was written against, so it
belongs in the client's own source and not in its configuration.

Three paths are **not** versioned, and `versions.py` says why: `/health`, which
answers a load balancer, and the two relays, `/proxy/{path}` and `/stream`.
Those take a URL and hand back bytes; there is no schema to version, and their
addresses live inside an `.m3u8` a player is halfway through and inside a
browser cache that was told to hold them for a week. A version bump that moved
them would break every one and buy nothing.

Adding a version is a line in `versions.py` — a version is a tuple of routers,
so the modules that did not change are the same objects rather than copies.

## Running it

```bash
docker compose up -d postgres        # port 5433 — 5432 is taken on this machine
uv run alembic upgrade head
uv run api                           # http://127.0.0.1:8000/docs
```

## POST /api/v1/init

The only endpoint so far. Called on every launch, safe to repeat.

```bash
curl -s localhost:8000/api/v1/init -H 'content-type: application/json' -d '{
  "id": "3f2a1e40-9a1c-4f0e-8b1d-2c9e7a5b6d10",
  "platform": "android",
  "vendor": "com.android.vending",
  "ver": "1.0.0"
}' | jq
```

```json
{
  "install": {"id": "3f2a…", "first_run": true, "registered_at": "…"},
  "session": {"token": "…", "expires_at": "…"},
  "update": {"action": "none", "channel": "store", "current": "1.0.0",
             "latest": "1.0.0", "minimum": "0.0.0", "url": "https://play.google.com/…"},
  "features": {},
  "server_time": "…"
}
```

Send the token back as `Authorization: Bearer …` on the next launch and
`session.token` comes back `null` — the one you have still works, and it is not
repeated at you.

`vendor` decides two things. `com.android.vending` means Google installed it, so
the update channel is `store` (a build that sideloads its own APK gets pulled
from the shop) and every name in `API_STORE_DISABLED_FEATURES` comes back off.
Anything else updates itself from `API_SELF_UPDATE_URL`; `web` has nothing to
update at all. Sending `vendor` from a non-android platform is refused, not
ignored — outside android there is no installer package to report.


## Signing a television in

Typing an email with a D-pad is miserable, so the box never asks for one.

```
TV     POST /auth/device            → {code, secret, verify_path}
TV     shows the code and a QR of verify_path
phone  registers or logs in with the API, as itself
phone  POST /auth/device/approve    {code}
TV     POST /auth/device/collect    {secret}   → a session of its own
```

Two secrets, and deliberately not the same one. The code is short because it is
read off a screen, so knowing it only lets somebody *approve*. The secret never
leaves the television, so an approval given to the wrong person still hands the
session to the box that asked and to nothing else. Collecting works once.

## Remote control

Same idea, no new secrets at all: **you may drive a box you are signed in on.**
That relation already lives in `auth_sessions`, so the module has no schema.

```
GET  /devices                    what you may drive
POST /device/{id}/rpc            {"id": "…", "method": "play", "params": {…}}
GET  /device/{id}/events         SSE — what that box is doing
GET  /device/events              SSE — the box's own commands
POST /device/state               the box saying what it is doing
```

The box never names itself: its session already says which install it is, and a
device that could name itself could name somebody else's. A device you are not
signed in on answers `404`, not `403` — telling a stranger a device exists is
telling them something.

SSE rather than a websocket because of what the connection has to survive: a
television holds it for months across sleeping Wi-Fi, and an `EventSource`
reconnects by itself. Nothing carries an event `id`, because resumption would
mean replaying, and replaying a command is exactly wrong — an instruction is
about *now*, and a box that missed "play" must not act on it a minute later.
State is a fact rather than an instruction, so the newest one is handed over the
moment a stream opens.

The bus behind it is in-memory and process-wide. Two processes behind a balancer
need a real one — a `POST` landing on A while the stream is held by B still has
to arrive — and that is a Redis implementation of the same protocol, built in
`remote/deps.py`, with nothing else changing.


## Television

Free channels from sweet.tv. No account anywhere — a uuid stands in for one.

```
GET  /tv/channels                       the list, with categories
GET  /tv/channels/{id}/schedule?day=    one channel's programmes for one day
POST /tv/channels/{id}/stream           a lease on the stream
```

Open on purpose: these are free channels, and requiring an account would shut
anonymous boxes out of television altogether. What stands between this and abuse
is a cache on the reads and a ceiling on the one call that costs the other side
work.

**Only the list has to come through here.** Of the four hosts involved, only the
catalogue's sends no CORS headers at all. The schedule, the stream lease and the
video — master playlist, variants and segments alike — all answer
`access-control-allow-origin: *`, and none of them looks at `Origin` or
`Referer`. So the video is played directly by the client: relaying it would
spend bandwidth fixing a problem nobody has. Measured, not assumed.

A stream is a lease, not an address: it carries a session and goes stale after
`refresh_in`. It is never cached — two viewers handed the same session is how
both of them get dropped.
