"""The catalogue.

The parsing belongs to the `kinostrain` package and is tested there against
captured payloads. What is tested here is what this module adds: which answers
are held and which deliberately are not, and a failure upstream that reads
correctly on the way out.
"""

import json
from collections.abc import Callable

import httpx2
import pytest
from api.core.cache import Cache
from api.main import create_app
from api.modules.catalogue.deps import catalogue_service
from api.modules.catalogue.service import CatalogueService, RailKey
from conftest import BASE
from kinostrain import AsyncKinostrainApi, CatalogFilters, ContentCard
from kinostrain.transport import Request, Response

CARD = {
    "name": "Сусіди зверху",
    "originalName": "Upstairs",
    "slug": "susidi-zverhu",
    "type": "movie",
    "format": "film",
    "posterUrl": "https://p/1.webp",
    "genres": [{"name": "Комедія", "slug": "komedia"}],
    "imdbMark": 7.6,
    "yearStart": 2026,
    "time": "107 хв",
}

PAGE = {"data": [CARD], "meta": {"page": 1, "perPage": 24, "total": 100, "totalPages": 5}}
LIST = {"data": [CARD]}
FILTERS = {
    "movie": {
        "genres": {
            "popular": [{"name": "Бойовик", "slug": "bojovik"}],
            "other": [{"name": "Вестерн", "slug": "vestern"}],
        },
        "years": [{"name": "2026", "slug": "2026"}, {"name": "2006-2010", "slug": "2006-2010"}],
        "totalCount": 3577,
    }
}
DETAILS = {
    "data": {
        "id": 458,
        "name": "Сусіди зверху",
        "originalName": "Upstairs",
        "slug": "susidi-zverhu",
        "type": "movie",
        "format": "film",
        "posterUrl": "https://p/1.webp",
        "seasons": [
            {
                "id": 1,
                "number": 1,
                "players": ["ashdi", "tortuga"],
                "playerData": {"ashdi": [{"name": "DniproFilm", "link": "https://a/1"}]},
            }
        ],
        "cast": [{"name": "А", "originalName": "A", "slug": "a", "character": "Він", "gender": 2}],
    }
}
SEARCH = {"data": [CARD | {"highlight": {"name": "Сусіди <mark>зверху</mark>"}}]}


class Upstream:
    """kinostrain, answered from memory, counting what it was asked."""

    def __init__(self, answer: Callable[[Request], Response] | None = None) -> None:
        self.requests: list[Request] = []
        self._answer = answer or self._default

    async def send(self, request: Request) -> Response:
        self.requests.append(request)
        return self._answer(request)

    async def aclose(self) -> None:
        pass

    @property
    def urls(self) -> list[str]:
        return [request.url for request in self.requests]

    def asked(self, fragment: str) -> int:
        return len([url for url in self.urls if fragment in url])

    @staticmethod
    def _default(request: Request) -> Response:
        body: object = {}
        if "/catalog/filters" in request.url:
            body = FILTERS
        elif "/catalog" in request.url:
            body = PAGE
        elif "/trending" in request.url or "/slider" in request.url:
            body = LIST
        elif "/search" in request.url:
            body = SEARCH
        elif "/persons" in request.url:
            body = {"data": [], "meta": {"page": 1, "perPage": 24, "total": 0, "totalPages": 0}}
        elif "/content/" in request.url:
            body = DETAILS
        return Response(status_code=200, body=json.dumps(body).encode())


def serving(upstream: Upstream) -> CatalogueService:
    return CatalogueService(
        AsyncKinostrainApi(upstream),  # type: ignore[arg-type]
        Cache[str, CatalogFilters](ttl=300.0),
        Cache[RailKey, tuple[ContentCard, ...]](ttl=300.0),
    )


@pytest.fixture
def upstream() -> Upstream:
    return Upstream()


@pytest.fixture
def catalogue(upstream: Upstream) -> CatalogueService:
    return serving(upstream)


@pytest.fixture
async def client(catalogue: CatalogueService) -> httpx2.AsyncClient:
    app = create_app()
    app.dependency_overrides[catalogue_service] = lambda: catalogue
    return httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url=BASE)


# --- what comes back ----------------------------------------------------------


async def test_a_catalogue_page(client: httpx2.AsyncClient) -> None:
    answer = await client.get("/catalogue/content", params={"type": "movie", "page": 1})

    assert answer.status_code == 200
    body = answer.json()
    assert body["meta"] == {
        "page": 1,
        "per_page": 24,
        "total": 100,
        "total_pages": 5,
        "has_next_page": True,
    }
    card = body["items"][0]
    assert card["name"] == "Сусіди зверху"
    assert card["type"] == "movie"
    # Assembled here so every client does not assemble it differently.
    assert card["year_label"] == "2026"
    assert card["is_series"] is False


async def test_a_section_upstream_grew_does_not_break_a_client(
    client: httpx2.AsyncClient,
) -> None:
    # `type` comes back null and `type_raw` keeps what was said, so a row is
    # shown rather than dropped.
    upstream = Upstream(
        lambda _: Response(
            status_code=200,
            body=json.dumps(
                {"data": [CARD | {"type": "documentary"}], "meta": PAGE["meta"]}
            ).encode(),
        )
    )
    app = create_app()
    app.dependency_overrides[catalogue_service] = lambda: serving(upstream)

    async with httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url=BASE) as http:
        card = (await http.get("/catalogue/content")).json()["items"][0]

    assert card["type"] is None
    assert card["type_raw"] == "documentary"


async def test_filters_are_grouped_by_section(client: httpx2.AsyncClient) -> None:
    body = (await client.get("/catalogue/filters")).json()

    assert list(body["by_type"]) == ["movie"]
    movie = body["by_type"]["movie"]
    assert [one["slug"] for one in movie["popular_genres"]] == ["bojovik"]
    assert movie["total_count"] == 3577
    # A year bucket that spans a range says so, so a client does not parse it.
    assert [one["is_range"] for one in movie["years"]] == [False, True]
    assert body["unknown_types"] == []


async def test_a_search_hit_carries_what_matched(client: httpx2.AsyncClient) -> None:
    body = (await client.get("/catalogue/search", params={"q": "зверху"})).json()

    assert body["items"][0]["card"]["slug"] == "susidi-zverhu"
    assert "<mark>" in body["items"][0]["highlighted_name"]


async def test_a_query_of_one_character_never_leaves_the_client(
    client: httpx2.AsyncClient, upstream: Upstream
) -> None:
    answer = await client.get("/catalogue/search", params={"q": "з"})

    assert answer.status_code == 200
    assert answer.json()["items"] == []
    assert upstream.asked("/search") == 0


async def test_a_title_in_full(client: httpx2.AsyncClient) -> None:
    body = (await client.get("/catalogue/content/susidi-zverhu")).json()

    assert body["id"] == 458
    assert body["is_playable"] is True
    season = body["seasons"][0]
    assert season["is_loaded"] is True
    assert season["is_episodic"] is False
    # `players` advertises two; only one carries a stream.
    assert season["players"] == ["ashdi", "tortuga"]
    assert season["available_players"] == ["ashdi"]


async def test_a_season_can_be_asked_for_by_number(
    client: httpx2.AsyncClient, upstream: Upstream
) -> None:
    await client.get("/catalogue/content/susidi-zverhu", params={"season": 3})

    assert "season=3" in upstream.urls[-1]


# --- what is held, and what is not -------------------------------------------


async def test_filters_are_asked_for_once(client: httpx2.AsyncClient, upstream: Upstream) -> None:
    for _ in range(4):
        await client.get("/catalogue/filters")

    assert upstream.asked("/catalog/filters") == 1


async def test_a_rail_is_held_per_section(client: httpx2.AsyncClient, upstream: Upstream) -> None:
    await client.get("/catalogue/trending", params={"type": "movie"})
    await client.get("/catalogue/trending", params={"type": "movie"})
    await client.get("/catalogue/trending", params={"type": "serial"})
    await client.get("/catalogue/slider", params={"type": "movie"})

    # Two sections of trending, and the slider is a different rail.
    assert upstream.asked("/trending") == 2
    assert upstream.asked("/slider") == 1


async def test_a_catalogue_page_is_never_held(
    client: httpx2.AsyncClient, upstream: Upstream
) -> None:
    # It is ordered by what changed, so a held page shows yesterday's answer.
    await client.get("/catalogue/content", params={"page": 1})
    await client.get("/catalogue/content", params={"page": 1})

    assert upstream.asked("/catalog?") == 2


async def test_a_title_is_never_held(client: httpx2.AsyncClient, upstream: Upstream) -> None:
    # A series fills in one season; holding the answer would pin everybody to
    # whichever one the first caller wanted.
    await client.get("/catalogue/content/susidi-zverhu")
    await client.get("/catalogue/content/susidi-zverhu")

    assert upstream.asked("/content/susidi-zverhu") == 2


async def test_five_asking_at_once_ask_upstream_once(
    catalogue: CatalogueService, upstream: Upstream
) -> None:
    import asyncio

    await asyncio.gather(*(catalogue.catalog_filters() for _ in range(5)))

    assert upstream.asked("/catalog/filters") == 1


# --- failures -----------------------------------------------------------------


async def test_a_slug_nobody_has_is_a_404_not_a_502() -> None:
    def answer(request: Request) -> Response:
        if "/content/" in request.url:
            return Response(status_code=404, body=b'{"message": "not found"}')
        return Upstream._default(request)

    app = create_app()
    app.dependency_overrides[catalogue_service] = lambda: serving(Upstream(answer))

    async with httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url=BASE) as http:
        got = await http.get("/catalogue/content/nope")

    # The request was fine and so was upstream — the title is simply not there.
    assert got.status_code == 404
    assert "nope" in got.json()["detail"]


async def test_a_failure_upstream_is_a_502() -> None:
    upstream = Upstream(lambda _: Response(status_code=503, body=b"down"))
    app = create_app()
    app.dependency_overrides[catalogue_service] = lambda: serving(upstream)

    async with httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url=BASE) as http:
        got = await http.get("/catalogue/trending")

    assert got.status_code == 502
    assert "kinostrain" in got.json()["detail"]


async def test_a_failed_rail_is_not_remembered_as_a_rail(
    catalogue: CatalogueService, upstream: Upstream
) -> None:
    from api.errors import Upstream as UpstreamError

    broken = Upstream(lambda _: Response(status_code=503, body=b"down"))
    service = serving(broken)

    with pytest.raises(UpstreamError):
        await service.trending()
    with pytest.raises(UpstreamError):
        await service.trending()

    # A failure must not be cached, or one bad minute empties the home screen
    # for the whole ttl.
    assert broken.asked("/trending") == 2
