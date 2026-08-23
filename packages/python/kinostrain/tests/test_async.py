"""The async client answers exactly like the sync one."""

import pytest
from conftest import AsyncFakeTransport, query_of
from kinostrain import AsyncKinostrainApi, ContentType, HTTPError, NetworkError


def api_for(transport: AsyncFakeTransport) -> AsyncKinostrainApi:
    return AsyncKinostrainApi(transport)  # type: ignore[arg-type]


async def test_catalog_parses_the_same_payload() -> None:
    transport = AsyncFakeTransport.fixture("catalog_movie_page1")
    page = await api_for(transport).catalog(type=ContentType.MOVIE, page=1)

    assert page.meta.total == 3436
    assert page[0].slug == "odna-mila-rozdil-drugij"
    assert query_of(transport.last_request) == {"type": "movie", "page": "1"}


async def test_content_resolves_episode_sources() -> None:
    details = await api_for(AsyncFakeTransport.fixture("content_details_serial")).content(
        "zovnisni-milini"
    )

    season = details.seasons[0]
    assert season.playable_episodes == (1, 2, 3)
    assert season.sources_for("ashdi", episode=1)[0].name == "Le-Doyen"


async def test_search_short_circuits_below_two_characters() -> None:
    transport = AsyncFakeTransport.fixture("search")

    assert await api_for(transport).search(" м ") == ()
    assert transport.requests == []


async def test_cards_short_circuits_on_an_empty_slug_list() -> None:
    transport = AsyncFakeTransport.fixture("content_cards")

    assert await api_for(transport).cards([]) == ()
    assert transport.requests == []


async def test_maps_a_non_2xx_status_to_http_error() -> None:
    with pytest.raises(HTTPError) as caught:
        await api_for(AsyncFakeTransport.json("{}", status_code=404)).content("nope")

    assert caught.value.is_not_found


async def test_wraps_a_transport_failure_in_network_error() -> None:
    boom = OSError("connection reset")

    with pytest.raises(NetworkError) as caught:
        await api_for(AsyncFakeTransport.failing(boom)).trending()

    assert caught.value.cause is boom


async def test_the_context_manager_closes_the_transport() -> None:
    transport = AsyncFakeTransport.json('{"data": []}')

    async with api_for(transport) as api:
        await api.trending()

    assert transport.closed
