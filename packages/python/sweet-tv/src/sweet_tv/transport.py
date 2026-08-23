"""The seam between this client and whatever performs the I/O.

Deliberately minimal: this API needs a `GET` and a JSON `POST`, so an adapter
for any HTTP library is a dozen lines. The protocols are structural — nothing
has to import this module or subclass anything to satisfy them.

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
    """One request the client wants performed."""

    #: `GET` or `POST`, upper-case.
    method: str
    url: str
    headers: Mapping[str, str] = field(default_factory=lambda: EMPTY)
    #: Already-encoded JSON, or `None` for a body-less request.
    body: bytes | None = None

    def __str__(self) -> str:
        return f"{self.method} {self.url}"


@dataclass(frozen=True, slots=True)
class Response:
    """What came back, with the payload left as bytes.

    Bytes on purpose: this API answers `application/json` with no charset, and a
    library that guesses latin-1 from that turns every Ukrainian title into
    mojibake. The decoding happens here, as UTF-8.
    """

    status_code: int
    body: bytes
    headers: Mapping[str, str] = field(default_factory=lambda: EMPTY)

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

    @property
    def is_success(self) -> bool:
        return 200 <= self.status_code < 300


@runtime_checkable
class Transport(Protocol):
    def send(self, request: Request) -> Response: ...

    def close(self) -> None: ...


@runtime_checkable
class AsyncTransport(Protocol):
    async def send(self, request: Request) -> Response: ...

    async def aclose(self) -> None: ...
