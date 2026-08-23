# httpkit

The default engine. httpx underneath, with rotating proxies and retries on the
statuses that mean "slow down". Nothing site-specific lives here.

The scraping libraries in this repo **do not depend on this package**. They
declare a structural protocol of their own, and what's here happens to satisfy
it — which is what lets you swap the engine for `http.client`, raw sockets, or a
canned response, without touching them.

```python
from httpkit import build_fetcher, build_async_fetcher, resolve_pool

pool = resolve_pool("http://user:pass@gate.provider.com:7000")

with build_fetcher(proxy=pool) as fetcher:
    resolve(url, fetcher=fetcher)

async with build_async_fetcher(proxy=pool) as fetcher:
    await aresolve(url, fetcher=fetcher)
```

A fetcher is one method:

```python
fetcher.fetch(url, referer=None) -> Fetched(text=..., url=...)
```

`Fetched.url` is the address *after* redirects, because relative links have to
resolve against where the page really came from.

## Proxy spec

| form                                     | meaning                                   |
|------------------------------------------|-------------------------------------------|
| `http://user:pass@gate.example.com:7000` | one gateway — the provider rotates the IP |
| `http://a:8000,http://b:8000`            | a list, used round-robin                  |
| `@proxies.txt`                           | one URL per line, `#` comments allowed    |

`resolve_pool(spec)` takes the flag value first and falls back to the `PROXY_URL`
environment variable. **Only applications call it** — a library that reads the
environment has a hidden input, which is exactly what this package exists to
keep out of them.

## Retries

`RetryPolicy` decides *what* to retry and *how long* to wait; the sync and async
transports share that one object and differ only in how they sleep. So:

- retries `408, 425, 429, 500, 502, 503, 504` and transport errors, 3 times by default;
- honours `Retry-After` when the server sends a number of seconds;
- otherwise backs off exponentially (1s, 2s, 4s…, capped at 30s) with jitter, so
  parallel workers don't all come back at the same moment;
- takes the **next proxy** on each attempt, so a retry leaves the address that
  was just refused.

It all sits at the transport layer, so every call site gets it without asking.

Keep-alive is switched off whenever a proxy is configured: a rotating gateway
gives out a new exit IP per connection, and reusing the connection would pin you
to the one that just got rate-limited.
