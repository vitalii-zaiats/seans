"""What actually goes on the wire."""

import json

from conftest import FakeTransport, path_of, query_of
from kinostrain import ContentType, KinostrainApi

EMPTY_PAGE = '{"data": [], "meta": {"page": 1, "perPage": 24, "total": 0, "totalPages": 0}}'
EMPTY_LIST = '{"data": []}'


def api_for(transport: FakeTransport, **kwargs: object) -> KinostrainApi:
    return KinostrainApi(transport, **kwargs)  # type: ignore[arg-type]


def test_omits_null_query_parameters() -> None:
    transport = FakeTransport.json(EMPTY_PAGE)
    api_for(transport).catalog(type=ContentType.MOVIE, page=2)

    assert query_of(transport.last_request) == {"type": "movie", "page": "2"}


def test_sends_no_query_at_all_when_every_parameter_is_none() -> None:
    transport = FakeTransport.json(EMPTY_PAGE)
    api_for(transport).catalog()

    assert transport.last_request.url == "https://api.kinostrain.com/api/catalog"


def test_uses_the_hyphenated_slug_for_compound_content_types() -> None:
    transport = FakeTransport.json(EMPTY_LIST)
    api_for(transport).trending(type=ContentType.CARTOON_SERIES)

    assert query_of(transport.last_request)["type"] == "cartoon-series"


def test_joins_several_genres_with_commas() -> None:
    transport = FakeTransport.json(EMPTY_PAGE)
    api_for(transport).catalog(genres=["bojovik", "drama"])

    assert query_of(transport.last_request)["genres"] == "bojovik,drama"


def test_drops_an_empty_genre_list() -> None:
    transport = FakeTransport.json(EMPTY_PAGE)
    api_for(transport).catalog(genres=[])

    assert "genres" not in query_of(transport.last_request)


def test_escapes_the_slug_of_a_content_request() -> None:
    transport = FakeTransport.fixture("content_details")
    api_for(transport).content("a b/c")

    assert path_of(transport.last_request) == "/api/content/a%20b%2Fc"


def test_honours_a_custom_base_url_and_merges_extra_headers() -> None:
    transport = FakeTransport.json(EMPTY_LIST)
    api = api_for(
        transport,
        base_url="https://proxy.example/api/",
        headers={"Origin": "https://kinostrain.com"},
    )
    api.trending()

    request = transport.last_request
    assert request.url == "https://proxy.example/api/trending"
    assert request.headers["Origin"] == "https://kinostrain.com"
    assert request.headers["Accept"] == "application/json"


def test_posts_the_slug_list_as_a_json_body() -> None:
    transport = FakeTransport.fixture("content_cards")
    api_for(transport).cards(["lihtari", "grifini-sim-anin"])

    request = transport.last_request
    assert request.method == "POST"
    assert request.headers["Content-Type"] == "application/json"
    assert json.loads(request.body or b"") == {"slugs": ["lihtari", "grifini-sim-anin"]}


def test_does_not_call_the_api_for_an_empty_slug_list() -> None:
    transport = FakeTransport.fixture("content_cards")

    assert api_for(transport).cards([]) == ()
    assert transport.requests == []


def test_addresses_comments_by_numeric_id() -> None:
    transport = FakeTransport.fixture("comments_empty")
    api_for(transport).comments(458, page=2)

    assert path_of(transport.last_request) == "/api/content/458/comments"
    assert query_of(transport.last_request) == {"page": "2"}


def test_asks_for_one_season_by_number() -> None:
    transport = FakeTransport.fixture("content_details_serial")
    api_for(transport).content("zovnisni-milini", season=2)

    assert query_of(transport.last_request) == {"season": "2"}


def test_sends_no_season_parameter_when_none_was_asked_for() -> None:
    transport = FakeTransport.fixture("content_details_serial")
    api_for(transport).content("zovnisni-milini")

    assert query_of(transport.last_request) == {}


def test_sends_the_query_and_the_limit() -> None:
    transport = FakeTransport.fixture("search")
    api_for(transport).search("  мерц  ", limit=5)

    assert query_of(transport.last_request) == {"q": "мерц", "limit": "5"}


def test_does_not_call_the_api_below_two_characters() -> None:
    transport = FakeTransport.fixture("search")

    assert api_for(transport).search("м") == ()
    assert transport.requests == []


def test_close_closes_the_transport() -> None:
    transport = FakeTransport.json(EMPTY_LIST)
    with api_for(transport):
        pass

    assert transport.closed
