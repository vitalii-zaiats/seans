# kinostrain

Typed Python client for the public [kinostrain.com](https://kinostrain.com) content
API — catalog, filters, trending, slider, search, persons, content details,
comments. A port of the Dart `kinostrain_api` package.

**Why Python.** The API answers
`access-control-allow-origin: https://kinostrain.com`, so a browser on any other
origin is blocked by CORS. Server-side there is no such problem: this client is
what your own proxy calls, and the browser talks to the proxy.

```bash
pip install kinostrain
```

```python
from kinostrain import ContentType, KinostrainApi

with KinostrainApi() as api:
    for card in api.catalog(type=ContentType.MOVIE, page=1):
        print(card.name, card.year_label, card.imdb_mark)

    details = api.content("zlovisni-merci-u-vogni")
    season = details.first_playable_season
    for source in season.sources_for("ashdi"):
        print(source.name, source.link)
```

Async is the same surface, awaited:

```python
from kinostrain import AsyncKinostrainApi

async with AsyncKinostrainApi() as api:
    hits = await api.search("мерц")
```

## Transport

The client performs no I/O itself: it talks to a `Transport` — a structural
`Protocol`, so nothing has to subclass or import anything to satisfy it. With no
transport supplied it builds one on httpx.

```python
import httpx
from kinostrain import KinostrainApi
from kinostrain.transports.httpx import HttpxTransport

# Your own httpx client — a connection pool, retries, rotating proxies.
# An `httpx.Client` from `httpkit.build_client` drops straight in.
api = KinostrainApi(HttpxTransport(httpx.Client(timeout=5.0)))
```

An implementation has two rules: do **not** raise on a non-2xx status (return
the response and let the client raise `HTTPError`), and do raise on socket, DNS,
TLS or timeout failures (the client wraps them in `NetworkError`).

## Things the API does that the models have opinions about

- **`playerData` has two shapes.** A film's map is keyed by provider; a series'
  is keyed by episode number with providers one level in. `Season` parses both
  and hands them out through the same `sources_for(provider, episode=...)`.
- **A series returns every season but fills in one.** The rest arrive empty from
  `/content/{slug}?season=N`. An empty season means "not fetched yet", not
  "nothing to watch" — `Season.is_loaded` tells them apart.
- **`players` is a wish list.** A provider listed there may carry no stream;
  `Season.available_players()` is what actually plays.
- **Unknown values do not break parsing.** A sixth content section parses as
  `type=None` with `type_raw` intact; a missing *required* field raises
  `SerializationError` naming it.
