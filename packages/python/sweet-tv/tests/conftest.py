"""A transport that answers from memory, and the payloads it answers with.

The fixtures are the same JSON files the Dart package is tested against, copied
from `movies-api/packages/sweet_tv/test/fixtures` — captured from real traffic.
Testing the port against them is what makes it a port rather than a rewrite.
"""

from collections.abc import Callable
from pathlib import Path

from sweet_tv.transport import Request, Response

FIXTURES = Path(__file__).parent / "fixtures"


def fixture(name: str) -> str:
    return (FIXTURES / f"{name}.json").read_text(encoding="utf-8")


class FakeTransport:
    """Answers from memory and records what it was asked for."""

    def __init__(self, handler: Callable[[Request], Response]) -> None:
        self._handler = handler
        self.requests: list[Request] = []
        self.closed = False

    @classmethod
    def json(cls, body: str, *, status_code: int = 200) -> "FakeTransport":
        return cls(lambda _: Response(status_code=status_code, body=body.encode()))

    @classmethod
    def fixture(cls, name: str, *, status_code: int = 200) -> "FakeTransport":
        return cls.json(fixture(name), status_code=status_code)

    @classmethod
    def failing(cls, error: BaseException) -> "FakeTransport":
        def raise_it(_: Request) -> Response:
            raise error

        return cls(raise_it)

    @property
    def last_request(self) -> Request:
        return self.requests[-1]

    def send(self, request: Request) -> Response:
        self.requests.append(request)
        return self._handler(request)

    def close(self) -> None:
        self.closed = True


class AsyncFakeTransport(FakeTransport):
    """The same double, awaited."""

    async def send(self, request: Request) -> Response:  # type: ignore[override]
        self.requests.append(request)
        return self._handler(request)

    async def aclose(self) -> None:
        self.closed = True
