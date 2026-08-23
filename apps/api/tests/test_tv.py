"""Free-to-air television.

The parsing is the `sweet-tv` package's business and is tested there against
captured payloads. What is tested here is what this module adds: a cache, a
ceiling, and a refusal that reads correctly on the way out.
"""

import json
from collections.abc import Callable, Iterator

import httpx2
import pytest
from api.core.cache import Cache
from api.core.throttle import Throttle
from api.main import create_app
from api.modules.tv.deps import tv_service
from api.modules.tv.service import STREAM_BURST, STREAMS_PER_SECOND, TvService
from sweet_tv import AsyncSweetTv, Catalogue, Device, Schedule
from sweet_tv.transport import Request, Response

CHANNELS = {
    "channels": [
        {
            "id": 3554,
            "slug": "3554-originals",
            "name": "SWEET.TV Originals HD",
            "icon_v2_url": "http://static.sweet.tv/icon.png",
            "category": [27, 1000],
            "available_without_auth": True,
            "catchup": True,
            "catchup_duration": 7,
            "epg_now": "Ховаючи колишню Серія 1",
        }
    ],
    "categories": [
        {"id": 27, "slug": "films", "title": "Фільмові", "order": 4},
        {"id": 1000, "slug": None, "title": "Всi", "order": 1},
    ],
}

PROGRAMMES = [
    {"id": 1, "text": "Ранок", "time_start": 1787443736, "time_stop": 1787446560},
    {"id": 2, "text": "Новини", "time_start": 1787446560, "time_stop": 1787449292},
]

STREAM = {
    "result": "OK",
    "stream_id": 468438388,
    "update_interval": 300,
    "url": "https://stitch-ua5.fastad.pro/main.m3u8?c=3554",
    "http_stream": {"host": {"address": "stitch-ua5.fastad.pro", "port": 80}, "url": "/main.m3u8"},
    "chrome_cast_url": "https://hls.sweet.tv/direct.m3u8",
}


class Upstream:
    """sweet.tv, answered from memory, counting what it was asked."""

    def __init__(self, answer: Callable[[Request], Response] | None = None) -> None:
        self.requests: list[Request] = []
        self._answer = answer or self._default

    async def send(self, request: Request) -> Response:
        self.requests.append(request)
        return self._answer(request)

    async def aclose(self) -> None:
        pass

    @property
    def paths(self) -> list[str]:
        return [request.url for request in self.requests]

    @staticmethod
    def _default(request: Request) -> Response:
        body: object = {}
        if "channel_list" in request.url:
            body = CHANNELS
        elif "/epg/" in request.url:
            body = PROGRAMMES
        elif "OpenStream" in request.url:
            body = STREAM
        return Response(status_code=200, body=json.dumps(body).encode())


def serving(upstream: Upstream) -> TvService:
    return TvService(
        AsyncSweetTv(upstream, device=Device(uuid="test")),  # type: ignore[arg-type]
        Cache[str, Catalogue](ttl=300.0),
        Cache[tuple[int, object], Schedule](ttl=300.0),  # type: ignore[arg-type]
        Throttle[str](rate=STREAMS_PER_SECOND, burst=STREAM_BURST),
    )


@pytest.fixture
def upstream() -> Upstream:
    return Upstream()


@pytest.fixture
def tv(upstream: Upstream) -> Iterator[TvService]:
    yield serving(upstream)


@pytest.fixture
async def client(tv: TvService) -> httpx2.AsyncClient:
    app = create_app()
    app.dependency_overrides[tv_service] = lambda: tv
    return httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url="http://test")


# --- the list ----------------------------------------------------------------


async def test_the_channel_list_comes_through_us(
    client: httpx2.AsyncClient, upstream: Upstream
) -> None:
    answer = await client.get("/tv/channels")

    assert answer.status_code == 200
    body = answer.json()
    assert [one["name"] for one in body["items"]] == ["SWEET.TV Originals HD"]
    assert body["items"][0]["catchup_days"] == 7
    assert body["items"][0]["now_playing"] == "Ховаючи колишню Серія 1"
    # In the order the site shows them, which is not the order they arrive in.
    assert [one["title"] for one in body["categories"]] == ["Всi", "Фільмові"]
    assert body["categories"][0]["is_all"] is True


async def test_an_icon_is_handed_out_over_https(client: httpx2.AsyncClient) -> None:
    # The catalogue writes them as plain http, which a page on https refuses as
    # mixed content.
    body = (await client.get("/tv/channels")).json()

    assert body["items"][0]["icon_url"] == "https://static.sweet.tv/icon.png"


async def test_the_list_is_fetched_once_however_many_ask(
    client: httpx2.AsyncClient, upstream: Upstream
) -> None:
    for _ in range(5):
        assert (await client.get("/tv/channels")).status_code == 200

    assert len([url for url in upstream.paths if "channel_list" in url]) == 1


async def test_the_list_is_fetched_once_when_five_ask_at_the_same_moment(
    tv: TvService, upstream: Upstream
) -> None:
    import asyncio

    # Without single-flight a cold start with fifty boxes waking together is
    # fifty identical requests to somebody else's service.
    await asyncio.gather(*(tv.channels() for _ in range(5)))

    assert len([url for url in upstream.paths if "channel_list" in url]) == 1


# --- the schedule -------------------------------------------------------------


async def test_a_day_of_programmes(client: httpx2.AsyncClient) -> None:
    answer = await client.get("/tv/channels/3554/schedule", params={"day": "2026-08-21"})

    assert answer.status_code == 200
    body = answer.json()
    assert body["channel_id"] == 3554
    assert body["day"] == "2026-08-21"
    assert [one["title"] for one in body["items"]] == ["Ранок", "Новини"]
    assert body["items"][0]["start"].endswith("Z") or "+" in body["items"][0]["start"]


async def test_the_day_defaults_to_today(client: httpx2.AsyncClient, upstream: Upstream) -> None:
    from datetime import date

    await client.get("/tv/channels/3554/schedule")

    assert f"{date.today():%d-%m-%Y}" in upstream.paths[-1]


async def test_a_channel_nobody_has_is_a_404(client: httpx2.AsyncClient) -> None:
    # Not an empty day: those read the same to a client and mean something else.
    assert (await client.get("/tv/channels/999/schedule")).status_code == 404


async def test_a_day_upstream_never_published_is_empty_rather_than_an_error() -> None:
    def answer(request: Request) -> Response:
        if "/epg/" in request.url:
            return Response(status_code=404, body=b"not found")
        return Upstream._default(request)

    upstream = Upstream(answer)
    app = create_app()
    app.dependency_overrides[tv_service] = lambda: serving(upstream)

    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url="http://test"
    ) as http:
        got = await http.get("/tv/channels/3554/schedule")

    assert got.status_code == 200
    assert got.json()["items"] == []


# --- the stream ---------------------------------------------------------------


async def test_a_stream_is_a_lease(client: httpx2.AsyncClient) -> None:
    answer = await client.post("/tv/channels/3554/stream")

    assert answer.status_code == 200
    body = answer.json()
    assert body["channel_id"] == 3554
    assert body["url"].startswith("https://stitch-")
    assert body["plain_url"] == "http://stitch-ua5.fastad.pro/main.m3u8"
    assert body["direct_url"] == "https://hls.sweet.tv/direct.m3u8"
    assert body["refresh_in"] == 300


async def test_use_proxy_points_every_address_at_us(client: httpx2.AsyncClient) -> None:
    """The browser's case.

    The stitching host answers no `access-control-allow-origin` at all, so a
    page cannot read the playlist however politely it asks. With the flag every
    address comes back pointing at `/stream`, which can.
    """
    answer = await client.post("/tv/channels/3554/stream", params={"use_proxy": True})

    assert answer.status_code == 200
    body = answer.json()
    assert body["url"] == ("/stream?url=https%3A%2F%2Fstitch-ua5.fastad.pro%2Fmain.m3u8%3Fc%3D3554")
    assert body["plain_url"] == "/stream?url=http%3A%2F%2Fstitch-ua5.fastad.pro%2Fmain.m3u8"
    assert body["direct_url"] == "/stream?url=https%3A%2F%2Fhls.sweet.tv%2Fdirect.m3u8"
    # Relative, so one answer is right on localhost, behind a tunnel, and on a
    # hostname nobody has bought yet.
    assert not body["url"].startswith("http")


async def test_without_the_flag_the_addresses_belong_to_the_host(
    client: httpx2.AsyncClient,
) -> None:
    """Which is the case that should stay the default: a box plays the stream
    host-to-viewer, and routing that through us would spend our bandwidth
    fixing a rule that only browsers have."""
    body = (await client.post("/tv/channels/3554/stream")).json()

    assert body["url"].startswith("https://stitch-")
    assert body["direct_url"] == "https://hls.sweet.tv/direct.m3u8"


async def test_a_lease_is_never_cached(client: httpx2.AsyncClient, upstream: Upstream) -> None:
    # Two viewers handed the same session is how both of them get dropped.
    await client.post("/tv/channels/3554/stream")
    await client.post("/tv/channels/3554/stream")

    assert len([url for url in upstream.paths if "OpenStream" in url]) == 2


async def test_opening_a_stream_for_a_channel_nobody_has_is_a_404(
    client: httpx2.AsyncClient,
) -> None:
    assert (await client.post("/tv/channels/999/stream")).status_code == 404


async def test_a_channel_outside_the_free_tier_is_refused(
    client: httpx2.AsyncClient,
) -> None:
    def answer(request: Request) -> Response:
        if "OpenStream" in request.url:
            return Response(status_code=200, body=b'{"result": "NoAuth"}')
        return Upstream._default(request)

    app = create_app()
    app.dependency_overrides[tv_service] = lambda: serving(Upstream(answer))

    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url="http://test"
    ) as http:
        got = await http.post("/tv/channels/3554/stream")

    assert got.status_code == 403
    assert "not free" in got.json()["detail"]


async def test_a_stuck_finger_on_the_channel_button_is_throttled(
    client: httpx2.AsyncClient,
) -> None:
    statuses = {(await client.post("/tv/channels/3554/stream")).status_code for _ in range(20)}

    assert statuses == {200, 403}


async def test_a_failure_upstream_is_a_502_not_a_500() -> None:
    # Neither our fault nor the caller's: the request was fine and the thing
    # behind us was not.
    upstream = Upstream(lambda _: Response(status_code=503, body=b"down"))
    app = create_app()
    app.dependency_overrides[tv_service] = lambda: serving(upstream)

    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url="http://test"
    ) as http:
        got = await http.get("/tv/channels")

    assert got.status_code == 502
    assert "sweet.tv" in got.json()["detail"]


# --- the cache itself ---------------------------------------------------------


async def test_a_cached_value_expires() -> None:
    cache = Cache[str, int](ttl=0.0)
    calls = 0

    async def produce() -> int:
        nonlocal calls
        calls += 1
        return calls

    assert await cache.through("k", produce) == 1
    assert await cache.through("k", produce) == 2


async def test_forgetting_empties_it() -> None:
    cache = Cache[str, int](ttl=300.0)

    async def produce() -> int:
        return 7

    await cache.through("k", produce)
    assert cache.peek("k") == 7
    cache.forget()
    assert cache.peek("k") is None
