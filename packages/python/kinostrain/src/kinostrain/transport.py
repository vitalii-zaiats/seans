"""The seam between this client and whatever actually performs the I/O.

Deliberately minimal: the API only ever needs a `GET` and a JSON `POST`, so an
adapter for any HTTP library is a dozen lines. The protocols are *structural* —
nothing has to import this module or subclass anything to satisfy them, which
is what keeps `kinostrain` free of an opinion about httpx, aiohttp, retries or
proxies. `kinostrain.transports.httpx` ships the default; writing another is:

    class AiohttpTransport:
        def __init__(self, session): self._session = session

        async def send(self, request: Request) -> Response:
            async with self._session.request(
                request.method, request.url,
                headers=dict(request.headers), data=request.body,
            ) as response:
                return Response(
                    status_code=response.status,
                    body=await response.read(),
                    headers=dict(response.headers),
                )

        async def aclose(self) -> None: await self._session.close()

Two rules an implementation has to keep. It must **not** raise on a non-2xx
status — return the response and let the client raise `HTTPError`. Any other
failure (socket, DNS, TLS, timeout) it should raise; the client wraps it in
`NetworkError`.
"""

from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

EMPTY: Mapping[str, str] = {}


@dataclass(frozen=True, slots=True)
class Request:
    """A single HTTP request the client wants performed."""

    #: `GET` or `POST`, upper-case.
    method: str
    url: str
    headers: Mapping[str, str] = field(default_factory=lambda: EMPTY)
    #: Already-encoded body, or `None`. When set, `headers` carries
    #: `Content-Type: application/json`.
    body: bytes | None = None

    def __str__(self) -> str:
        return f"{self.method} {self.url}"


@dataclass(frozen=True, slots=True)
class Response:
    """The result of a `Request`, with the payload left as bytes.

    Bytes on purpose: the API answers `application/json` with no charset, and a
    library that guesses latin-1 from that mangles every Cyrillic title. The
    decoding happens here, as UTF-8, because that is what upstream actually
    sends.
    """

    status_code: int
    body: bytes
    headers: Mapping[str, str] = field(default_factory=lambda: EMPTY)

    @property
    def text(self) -> str:
        """The payload as UTF-8, never raising on malformed input."""
        return self.body.decode("utf-8", errors="replace")

    @property
    def is_success(self) -> bool:
        return 200 <= self.status_code < 300

    def __str__(self) -> str:
        return f"Response({self.status_code}, {len(self.body)} bytes)"


@runtime_checkable
class Transport(Protocol):
    """What `KinostrainApi` talks to instead of a concrete HTTP library."""

    def send(self, request: Request) -> Response: ...

    def close(self) -> None:
        """Releases whatever the underlying library holds, if anything."""
        ...


@runtime_checkable
class AsyncTransport(Protocol):
    """The same seam, awaited — what `AsyncKinostrainApi` talks to."""

    async def send(self, request: Request) -> Response: ...

    async def aclose(self) -> None: ...
