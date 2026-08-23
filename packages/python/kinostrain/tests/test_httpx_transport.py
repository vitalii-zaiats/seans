"""The default network stack, driven by httpx's own mock transport."""

from collections.abc import Callable

import httpx
import pytest
from kinostrain import KinostrainApi
from kinostrain.transport import Request
from kinostrain.transports.httpx import AsyncHttpxTransport, HttpxTransport

CYRILLIC = '{"data": [{"name": "Дріт мерця", "originalName": "Dead Man\'s Wire",'
CYRILLIC += ' "slug": "drit-merca", "type": "movie", "format": "film", "posterUrl": "p"}]}'


Handler = Callable[[httpx.Request], httpx.Response]


def mock_client(handler: Handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_hands_over_status_and_raw_bytes() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(418, content=b"\xd0\x9e\xd0\xba")

    transport = HttpxTransport(mock_client(handler))
    response = transport.send(Request(method="GET", url="https://example.test/x"))

    assert response.status_code == 418
    assert not response.is_success
    assert response.text == "Ок"


def test_does_not_raise_on_a_non_2xx_status() -> None:
    # The contract: the transport returns it, the client turns it into HTTPError.
    transport = HttpxTransport(mock_client(lambda _: httpx.Response(500, content=b"{}")))

    assert transport.send(Request(method="GET", url="https://example.test/x")).status_code == 500


def test_decodes_utf8_even_when_the_server_omits_the_charset() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        # Exactly what the real API sends: JSON with no charset on the type.
        return httpx.Response(
            200,
            content=CYRILLIC.encode(),
            headers={"content-type": "application/json"},
        )

    api = KinostrainApi(HttpxTransport(mock_client(handler)))

    assert api.trending()[0].name == "Дріт мерця"


def test_forwards_method_headers_and_body() -> None:
    seen: dict[str, httpx.Request] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["request"] = request
        return httpx.Response(200, content=b'{"data": []}')

    KinostrainApi(HttpxTransport(mock_client(handler))).cards(["lihtari"])

    request = seen["request"]
    assert request.method == "POST"
    assert request.headers["content-type"] == "application/json"
    assert request.read() == b'{"slugs": ["lihtari"]}'


def test_leaves_a_supplied_client_open() -> None:
    client = mock_client(lambda _: httpx.Response(200, content=b"{}"))
    HttpxTransport(client).close()

    assert not client.is_closed


def test_closes_a_client_it_created() -> None:
    transport = HttpxTransport(timeout=1.0)
    transport.close()

    assert transport._client.is_closed


async def test_async_transport_round_trips() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=CYRILLIC.encode())

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    transport = AsyncHttpxTransport(client)
    response = await transport.send(Request(method="GET", url="https://example.test/x"))

    assert response.status_code == 200
    assert "Дріт" in response.text
    await transport.aclose()
    assert not client.is_closed


def test_a_dead_connection_surfaces_as_a_network_error() -> None:
    from kinostrain import NetworkError

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("no route to host")

    with pytest.raises(NetworkError):
        KinostrainApi(HttpxTransport(mock_client(handler))).trending()
