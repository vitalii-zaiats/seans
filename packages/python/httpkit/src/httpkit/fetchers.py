"""Concrete requesters: what an app hands to a library.

The libraries here don't import this module — they declare a structural protocol
of their own and these classes happen to satisfy it. That's deliberate: it's what
keeps `ashdi-finder` and `crawlers` free of any opinion about proxies, retries or
even httpx.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from types import TracebackType

import httpx

from httpkit.client import build_async_client, build_client
from httpkit.proxies import ProxyPool

# Looking like a browser is a caller's policy, not a library's.
BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "uk-UA,uk;q=0.9,en;q=0.8",
}


@dataclass(frozen=True, slots=True)
class Fetched:
    """A page and where it actually came from, after redirects."""

    text: str
    url: str


def _headers(referer: str | None) -> dict[str, str] | None:
    return {"Referer": referer} if referer else None


class HttpxFetcher:
    """Sync requester. Owns its client, so it closes with it."""

    def __init__(self, client: httpx.Client) -> None:
        self._client = client

    def fetch(self, url: str, *, referer: str | None = None) -> Fetched:
        response = self._client.get(url, headers=_headers(referer))
        response.raise_for_status()
        return Fetched(text=response.text, url=str(response.url))

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "HttpxFetcher":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self.close()


class AsyncHttpxFetcher:
    """The same thing, awaited."""

    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client

    async def fetch(self, url: str, *, referer: str | None = None) -> Fetched:
        response = await self._client.get(url, headers=_headers(referer))
        response.raise_for_status()
        return Fetched(text=response.text, url=str(response.url))

    async def aclose(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> "AsyncHttpxFetcher":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()


def build_fetcher(
    *,
    proxy: ProxyPool | None = None,
    timeout: float = 20.0,
    headers: Mapping[str, str] | None = None,
    retries: int = 3,
) -> HttpxFetcher:
    return HttpxFetcher(
        build_client(
            headers=BROWSER_HEADERS if headers is None else headers,
            timeout=timeout,
            proxy=proxy,
            retries=retries,
        )
    )


def build_async_fetcher(
    *,
    proxy: ProxyPool | None = None,
    timeout: float = 20.0,
    headers: Mapping[str, str] | None = None,
    retries: int = 3,
) -> AsyncHttpxFetcher:
    return AsyncHttpxFetcher(
        build_async_client(
            headers=BROWSER_HEADERS if headers is None else headers,
            timeout=timeout,
            proxy=proxy,
            retries=retries,
        )
    )
