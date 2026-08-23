# super-movies-app

A monorepo: Python services, Dart clients and a landing site in one tree.

## Layout

```
apps/
  api/        Python HTTP API — /init, accounts, pairing, remote control
  tv/         Flutter launcher for an Android TV box, and its web build
  web/        Nuxt 4 + TS — the catalogue in a browser
  admin/      Vue 3 + TS dashboard — install statistics
  remote/     Vue 3 + TS — the page a QR code opens on a phone
  landing/    landing site — empty
packages/
  python/
    kinostrain/           client for the public kinostrain.com API (sync + async)
    sweet-tv/             client for sweet.tv's free channels (sync + async)
  dart/
    super_movies_api/     start-up, identity, pairing a television
    super_movies_remote/  the remote and the box — commands and state
contracts/    openapi.json (generated: `uv run openapi`) and proto/ — the
              contract between the API and its clients
deploy/       nginx snippets, and the one front door that puts every app and
              the API behind a single address
tools/
  sfx-generator/          procedural UI sounds and ambient loops for Android TV
```

Conventions live in [CLAUDE.md](CLAUDE.md).

## Why one repo rather than two

The Dart client and the Python API are tied together by one contract. In a
single repo, changing an endpoint and updating its client is one commit that
either passes CI as a whole or does not. Two repos buy version skew and
cross-repo pull requests instead. The toolchains do not collide: the uv
workspace lives in `pyproject.toml`, the pub workspace in `pubspec.yaml`, in
different subtrees. Splitting a monorepo later is cheap (`git subtree split`);
merging two repos into one is not.

## Python

```bash
uv sync --all-packages     # install every workspace member into ./.venv
uv run pytest -q
uv run ruff check .
uv run mypy apps/api/src packages/python/*/src
```

`tools/sfx-generator` is a standalone uv project with its own lock (numpy,
scipy) and is deliberately not a workspace member: `cd tools/sfx-generator && uv sync`.

## Dart

```bash
dart pub get               # one lock for the whole pub workspace
dart test packages/dart
dart analyze packages/dart
```

## Running the API

```bash
cd apps/api
docker compose up -d postgres      # port 5433 — 5432 is taken on this machine
uv run alembic upgrade head
uv run api                         # http://127.0.0.1:8000/docs
```

## Running the whole stack

```bash
docker compose up --build          # postgres, the API, and every web app on a port each
```

Ports: API 8000, admin 8081, remote 8082, launcher-on-the-web 8083
(`--profile tv`), web 8084.

## Showing it to somebody else

One address for everything, which is what a tunnel needs — ngrok's free plan
hands out exactly one:

```bash
cd apps/tv && flutter build web --release --base-href /box/ --dart-define=API=   # only for /box/
docker compose -f compose.yaml -f compose.edge.yaml up --build                   # localhost:8090

export NGROK_AUTHTOKEN=…           # dashboard.ngrok.com
docker compose -f compose.yaml -f compose.edge.yaml --profile ngrok up --build
docker compose -f compose.yaml -f compose.edge.yaml logs ngrok | grep -o 'https://[^ ]*ngrok[^ ]*'
```

| path | what |
| --- | --- |
| `/` | the web launcher (`apps/web`) |
| `/r/<code>` | the phone pairing page (`apps/remote`) |
| `/dashboard/` | install statistics (`apps/admin`) |
| `/box/` | the launcher's own web build (`apps/tv`, `--profile tv`) |
| `/catalogue/`, `/auth/`, `/init`, `/proxy/`, … | the API |

**Nothing is rebuilt when the tunnel address changes.** Every client here asks
for `/catalogue/…` with no host, so a bundle knows nothing about where it is
served from. The one exception is the Flutter build: it needs `--base-href` to
know its prefix, and `--dart-define=REMOTE=<public url>` if the QR code it draws
is to be scannable from a phone — a QR cannot carry a relative address.

`deploy/edge/nginx.conf.template` is the front door, and it carries the one rule
worth knowing: an app's prefix must never collide with an API path. That is why
the launcher is at `/box/` and not `/tv/`, and the dashboard at `/dashboard/`
and not `/admin/` — the API owns both of those.

## Deploying it

Five names, one certificate authority, and nothing else facing the internet:

| name | what | image |
| --- | --- | --- |
| `app.seans.com` | the web launcher, and `/r/<code>` for pairing | `apps/web`, `apps/remote` |
| `seans.com` | the same, once the apex is ours to serve | — |
| `api.seans.com` | the API — for clients that are **not** browsers | `apps/api` |
| `tv.seans.com` | the launcher as a web app / PWA | `apps/tv` |
| `remote.seans.com` | the same pairing page under its own name | `apps/remote` |
| `admin.seans.com` | install statistics | `apps/admin` |

```bash
cp deploy/prod.env.example .env        # DOMAIN, ACME_EMAIL, POSTGRES_PASSWORD
cd apps/tv && flutter build web --release     --dart-define=API= --dart-define=REMOTE=https://$DOMAIN
docker compose -f compose.prod.yaml up -d --build
```

DNS: a wildcard `A *` covers every subdomain. The apex needs its own record —
`*` never matches the bare name — and on `seans-kino.online` it currently cannot
be served at all: GoDaddy answers the apex with its own parking address
regardless of the `A @` in the editor, and the domain cannot move registrar
until 22 October. Hence `app.`, which is the canonical name until then; the apex
block stays in the Caddyfile so it starts working the day it is freed.

Caddy gets the certificates itself on first request; port 80 must be reachable
or it cannot.

Releases are cut from tags: `git tag v0.1.0 && git push --tags` builds the APK,
signs it and attaches it as `seans.apk`, which is what the downloads page links
to at `…/releases/latest/download/seans.apk`. Every push to `main` still leaves
an APK as a run artifact for thirty days.

**Browsers never talk to `api.`** Each app's own nginx proxies the API paths it
needs, so a page served from `seans.com` asks `seans.com` for its data — no
CORS, no base URL in any bundle, and nothing to rebuild when a hostname changes.
`api.seans.com` is the entrance for the Android box and the APK, which are not
browsers and do need an absolute address:

```bash
flutter build apk --release     --dart-define=API=https://api.seans.com     --dart-define=REMOTE=https://seans.com
```

`REMOTE` is the one thing a build must be told either way: it is what the QR
code carries, and a QR cannot hold a relative address.

`compose.prod.yaml` is self-contained rather than an overlay on `compose.yaml`,
because compose *appends* port lists and can never take one away — an overlay
could add the front door but not close the five plaintext ports behind it.

### From CI

`.github/workflows/deploy.yml` checks, builds, pushes and deploys — in that
order, each job refusing to start until the one before it passed. A pull request
stops after the checks; `main` goes all the way; a manual run with `tag` set to
an older commit is what a rollback looks like.

The server compiles nothing. It holds three files — the compose file, the
Caddyfile and an `.env` the playbook writes — and pulls five images from GHCR.
`deploy/ansible/deploy.yml` is the whole of it, and it needs no Ansible
collections: plain `ansible-core` is enough.

| kind | name | what |
| --- | --- | --- |
| variable | `DOMAIN` | the apex, e.g. `seans-kino.online` |
| variable | `ACME_EMAIL` | where Let's Encrypt writes |
| variable | `DEPLOY_ENABLED` | `true` to let a push reach the server |
| variable | `SELF_UPDATE_URL` | where the APK lives, if there is one |
| secret | `DEPLOY_HOST` | the server |
| secret | `DEPLOY_USER` | the account to ssh in as |
| secret | `ANSIBLE_VAULT_PASSWORD` | opens `deploy/ansible/secrets/deploy_key.vault` |
| secret | `POSTGRES_PASSWORD` | the database |
| secret | `CATALOGUE_PROXY` | an exit in Ukraine for the catalogue — see below |
| secret | `ANDROID_KEYSTORE` + `_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | signs the APK; without them it is signed with the debug key and says so |

`GITHUB_TOKEN` covers the registry — no secret needed for GHCR.

**The catalogue is geo-restricted and nothing else is.** kinostrain.com answers
a request from outside Ukraine with the metadata intact and `player_data`
empty — every title looks browsable and turns out to be unplayable. Measured:
the same title returns three players to a Ukrainian address and none to a German
one. `CATALOGUE_PROXY` points that one client at an exit in Ukraine. ashdi's
player pages, its CDN and sweet.tv all answer a foreign address perfectly well,
so no video is routed through it.

**The images land private even though the repository is public.** That is GHCR's
default and it does not stop a deploy: the playbook logs in with the same run's
token. It does stop `docker pull ghcr.io/…/seans-api` by hand, so make each
package public in its own settings if that is wanted.

The deploy key is committed, encrypted, under `deploy/ansible/secrets/`. That
directory's README says what that costs in a public repository and how to rotate
it.

First time on a fresh machine, install Docker with the tag that exists for it
and nothing else:

```bash
cd deploy/ansible && cp inventory.example.ini inventory.ini   # then edit it
ansible-playbook deploy.yml -i inventory.ini --tags bootstrap -e …
```

**One thing CI has to do that a laptop forgets:** the launcher's image packages
a Flutter bundle rather than building one, so the workflow builds `apps/tv` for
the web *before* the image job and hands it over as an artifact. Build any other
Flutter target locally and `apps/tv/build/web` is wiped — which is a confusing
`docker build` failure and the reason this is encoded in a job rather than in a
README line.

## What exists so far

**`POST /init`** — the first call an app makes, safe on every launch. It answers
with the install, an account, a session, the update plan and the feature flags.
Send no install id and nothing is written down at all: that is the "everything
stays on this device" case, and the answer still carries the update plan.

**Accounts** — a guest and a member are the same row, told apart by
`claimed_at`, so claiming an account keeps everything watched before it. Three
states, and the app moves between them in one direction: local → guest →
claimed.

**Pairing** — typing an email with a D-pad is miserable, so a television never
asks for one. It shows a code, a phone approves as itself, and the box collects
a session of its own. Two secrets, deliberately not the same one.

**Television** — sweet.tv's free channels: the list, the schedule and a stream
lease. Only the list has to come through the API; the video is played directly,
because the stream host allows any origin and ignores `Referer`.

**Remote control** — you may drive a box you are signed in on. Commands are
POSTs, state arrives on a server-sent event stream, and the ownership relation
already lives in `auth_sessions`, so the module has no schema of its own.
