"""The default network stack: httpx.

Two adapters, one blocking and one awaited, each satisfying the matching
protocol in `kinostrain.transport` structurally — neither subclasses anything.
httpx suits the seam exactly: it does not raise on a 4xx or 5xx (which the
client must see for itself, to raise `HTTPError`) and it does raise on socket,
DNS, TLS and timeout failures (which the client wraps in `NetworkError`).

Pass your own `httpx.Client` to reuse a connection pool, or to bring retries
and rotating proxies — an `httpx.Client` built by `httpkit.build_client` drops
straight in. The caller then owns it: `close()` leaves a supplied client open
and only shuts down one this transport created.
"""

from types import TracebackType

import httpx

from kinostrain.transport import Request, Response

DEFAULT_TIMEOUT = 20.0


def _as_response(response: httpx.Response) -> Response:
    # `.content` and not `.text`: the API omits the charset on
    # `application/json`, so letting httpx guess would mangle Cyrillic titles.
    return Response(
        status_code=response.status_code,
        body=response.content,
        headers=dict(response.headers),
    )


class HttpxTransport:
    """A blocking transport backed by `httpx.Client`."""

    def __init__(self, client: httpx.Client | None = None, *, timeout: float = DEFAULT_TIMEOUT):
        self._client = client or httpx.Client(timeout=timeout, follow_redirects=True)
        self._owns_client = client is None

    def send(self, request: Request) -> Response:
        return _as_response(
            self._client.request(
                request.method,
                request.url,
                headers=dict(request.headers),
                content=request.body,
            )
        )

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> "HttpxTransport":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self.close()


class AsyncHttpxTransport:
    """The same thing, awaited, backed by `httpx.AsyncClient`."""

    def __init__(
        self, client: httpx.AsyncClient | None = None, *, timeout: float = DEFAULT_TIMEOUT
    ):
        self._client = client or httpx.AsyncClient(timeout=timeout, follow_redirects=True)
        self._owns_client = client is None

    async def send(self, request: Request) -> Response:
        return _as_response(
            await self._client.request(
                request.method,
                request.url,
                headers=dict(request.headers),
                content=request.body,
            )
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def __aenter__(self) -> "AsyncHttpxTransport":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()
