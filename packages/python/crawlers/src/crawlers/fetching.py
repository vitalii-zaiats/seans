"""What this package needs from whoever does the talking — and nothing more.

Structural protocols, so nothing here imports an HTTP library or holds an opinion
about proxies, retries or headers. The caller decides all of that;
`httpkit.build_fetcher()` satisfies the shape without either side importing the
other, and so would a socket you drive yourself.

Deliberately a copy of the protocol in `ashdi-finder` rather than a shared
package: fifteen lines of duplication is the price of two libraries that don't
depend on each other or on a third one.
"""

from typing import Protocol


class Response(Protocol):
    @property
    def text(self) -> str: ...

    @property
    def url(self) -> str:
        """Where the page came from after redirects."""


class Fetcher(Protocol):
    def fetch(self, url: str, *, referer: str | None = None) -> Response: ...


class AsyncFetcher(Protocol):
    async def fetch(self, url: str, *, referer: str | None = None) -> Response: ...


class FetchError(Exception):
    """A page could not be fetched. The requester's own error is chained onto it."""
