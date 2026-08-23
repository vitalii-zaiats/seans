# super-movies-app — conventions

## Typing: no bare `dict`

**`-> dict`, `dict[str, Any]` and `Any` in a public signature are out.** The type
has to say what is inside. In order of preference:

1. **A DTO** — `@dataclass(frozen=True, slots=True)` with a `from_json`
   classmethod. The default for anything crossing a package boundary.
2. **A `TypedDict`** — when the shape genuinely has to stay a `dict`: JSON that
   travels on unchanged, a message on a bus, something handed to `json.dumps`.
3. **A `Protocol`** — when what matters is behaviour rather than fields.

```python
# no
def get_movie(slug: str) -> dict: ...
def parse(payload: dict[str, Any]) -> dict: ...

# yes
@dataclass(frozen=True, slots=True)
class Movie:
    slug: str
    title: str

def get_movie(slug: str) -> Movie: ...
```

**The one exception is a shape we genuinely do not know.** Then the loose type
stays, with a comment next to it saying *why* it was not narrowed and what to do
when the shape turns up. There are two of those today, and both are named:

- `KinostrainApi.comments()` returns `Page[JsonMap]`, because `data` was empty in
  every captured response and inventing fields blind is worse than saying so.
- The remote's command params and a device's state are `Mapping[str, JsonValue]`
  — an app payload the server deliberately does not interpret. `JsonValue` is a
  spelled-out recursive alias, not `Any`.

The same goes for collections: `tuple[Movie, ...]` rather than `list` in a DTO
field, so a frozen dataclass stays hashable and cannot be mutated from the side.

## A module never imports another module

Inside `apps/api`, each folder under `modules/` owns its tables, its queries, its
rules and its routes. What it needs from outside it **states itself**, in its own
`ports.py`, as a `Protocol` over `Literal`s. The provider satisfies that
structurally without ever having heard of it.

Two details make it work with no cross-module import at all:

- returned shapes are `Protocol`s, so a frozen dataclass in the provider
  satisfies one by having the right attributes;
- vocabularies are `Literal`s rather than a shared enum, so both sides spell out
  the same strings independently. If one side renames a value the mismatch shows
  up at the seam instead of leaking through to the wire.

`deps.py` (for HTTP) and `core/services.py` (for everything else) are the only
files allowed to know which service satisfies which port.

**The one sanctioned exception is an anticorruption layer**, and it must be named
for what it is. There is exactly one: `remote/adapters.py`, because "which boxes
may this person drive" is half an accounts question and half an installs
question, and something has to have met both.

A module's **service** is its public face. Its repository is private — reaching
past a service into another module's repository is not allowed even when it
would be shorter.

## Layout

```
apps/
  api/        Python HTTP API — /init, accounts, pairing, remote control
  mobile/     Flutter app (entry point)
  landing/    landing site
  admin/      Vue 3 + TS + SCSS dashboard (Vuetify) — install statistics
  web/        Nuxt 4 + TS — the catalogue in a browser, no box-only sections
packages/
  python/     pip packages, members of the uv workspace
  dart/       pub packages, members of the pub workspace
contracts/    the contract between the API and its clients: openapi.json for
              HTTP, proto/ for gRPC (described, not generated)
tools/        development utilities (sfx-generator is a standalone uv project,
              not a workspace member, and neither ruff nor mypy touches it)
```

## Python

One uv workspace for the whole repo. The root `pyproject.toml` is virtual
(`package = false`); members are `apps/*` and `packages/python/*`.

```bash
uv sync --all-packages    # install every member into ./.venv
uv run pytest -q
uv run ruff check .
uv run mypy apps/api/src packages/python/*/src
```

`--all-packages` is not optional: without it uv installs only the root's
dependencies and nothing imports.

Migrations are Alembic, async, with the URL coming from `api.settings` so
`alembic upgrade` and the running API can never point at different databases.

```bash
cd apps/api
docker compose up -d postgres     # port 5433 — 5432 is taken on this machine
uv run alembic upgrade head
uv run alembic check              # fails when the models have drifted
```

## Dart

One pub workspace, rooted at `pubspec.yaml`.

```bash
dart pub get
dart test packages/dart
dart analyze packages/dart
dart format packages/dart
```

## Style

A docstring explains **why**, not what the signature already says. A comment
belongs where the code does something non-obvious because of a real property of
the outside world — and then it names that property ("the API answers
`application/json` with no charset, so we decode UTF-8 ourselves").

## Gotchas worth knowing before you trip over them

- **Tests run on SQLite, production on Postgres.** Nothing in the schema is
  dialect-specific, and the one upsert is written as select-then-insert on
  purpose so it works on both. `core.models.UTCDateTime` exists because SQLite
  hands back naive datetimes and the first thing anybody does is compare one to
  `utcnow()`.
- **`httpx`/`httpx2` `ASGITransport` never returns from `client.stream()` when
  the body is endless.** SSE tests drive the route's generators directly over the
  process-wide bus instead; the POST that publishes still goes over HTTP, so the
  test is still end to end.
- **In Dart, do not use `async*` for anything that must be cancellable
  promptly.** A generator only notices its listener has gone when it next
  reaches a `yield`, so one asleep in a backoff ignores `cancel()` for the whole
  wait. Use a `StreamController` with `onCancel`, or a `StreamTransformer`.
- **The browser's `EventSource` cannot send an `Authorization` header.** A web
  client of the SSE endpoints needs an `EventStream` built on `fetch` with a
  `ReadableStream`. A token in the query string would work and would also land in
  every access log on the way.
