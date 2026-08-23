"""Every endpoint, reduced to what it sends and how to read the answer.

Both clients are built from these, so the sync and the async one cannot drift
apart on what an endpoint *is* — only on how they wait for it.
"""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from typing import TypedDict
from urllib.parse import quote

from kinostrain.errors import SerializationError
from kinostrain.jsonread import JsonMap, list_of, map_or_none
from kinostrain.models import (
    CatalogFilters,
    ContentCard,
    ContentDetails,
    ContentType,
    Page,
    Person,
    SearchResult,
)

#: A query below this many characters is answered with nothing at all upstream.
MIN_QUERY_LENGTH = 2


class CardsBody(TypedDict):
    """The only request body the API takes: a batch of slugs."""

    slugs: list[str]


@dataclass(frozen=True)
class Call[T]:
    """One request and the function that turns its JSON into a model."""

    #: `GET` or `POST`, upper-case.
    method: str
    path: str
    parse: Callable[[JsonMap], T]
    #: Entries whose value is `None` are dropped when the URL is built.
    query: Mapping[str, str | None] = field(default_factory=dict)
    #: A JSON body, or `None` for a body-less request.
    body: CardsBody | None = None


def _data_list[T](parse: Callable[[JsonMap], T]) -> Callable[[JsonMap], tuple[T, ...]]:
    """Reads a bare `{"data": [...]}` envelope — the endpoints without paging."""
    return lambda json: list_of(json, "data", parse)


def _data_page[T](parse: Callable[[JsonMap], T]) -> Callable[[JsonMap], Page[T]]:
    return lambda json: Page.from_json(json, parse)


def catalog(
    *,
    type: ContentType | None = None,
    page: int | None = None,
    genres: Sequence[str] | None = None,
    year: str | None = None,
) -> Call[Page[ContentCard]]:
    return Call(
        "GET",
        "/catalog",
        _data_page(ContentCard.from_json),
        query={
            "type": None if type is None else type.slug,
            "page": None if page is None else str(page),
            "genres": ",".join(genres) if genres else None,
            "year": year,
        },
    )


def catalog_filters() -> Call[CatalogFilters]:
    return Call("GET", "/catalog/filters", CatalogFilters.from_json)


def trending(*, type: ContentType | None = None) -> Call[tuple[ContentCard, ...]]:
    return Call(
        "GET",
        "/trending",
        _data_list(ContentCard.from_json),
        query={"type": None if type is None else type.slug},
    )


def slider(*, type: ContentType | None = None) -> Call[tuple[ContentCard, ...]]:
    return Call(
        "GET",
        "/slider",
        _data_list(ContentCard.from_json),
        query={"type": None if type is None else type.slug},
    )


def search(query: str, *, limit: int | None = None) -> Call[tuple[SearchResult, ...]]:
    return Call(
        "GET",
        "/search",
        _data_list(SearchResult.from_json),
        query={"q": query, "limit": None if limit is None else str(limit)},
    )


def persons(*, page: int | None = None) -> Call[Page[Person]]:
    return Call(
        "GET",
        "/persons",
        _data_page(Person.from_json),
        query={"page": None if page is None else str(page)},
    )


def content(slug: str, *, season: int | None = None) -> Call[ContentDetails]:
    def parse(json: JsonMap) -> ContentDetails:
        data = map_or_none(json, "data")
        if data is None:
            raise SerializationError(f"expected a `data` object for content `{slug}`")
        return ContentDetails.from_json(data)

    return Call(
        "GET",
        f"/content/{quote(slug, safe='')}",
        parse,
        query={"season": None if season is None else str(season)},
    )


def cards(slugs: Sequence[str]) -> Call[tuple[ContentCard, ...]]:
    return Call(
        "POST",
        "/content/cards",
        _data_list(ContentCard.from_json),
        body={"slugs": list(slugs)},
    )


def comments(content_id: int, *, page: int | None = None) -> Call[Page[JsonMap]]:
    return Call(
        "GET",
        f"/content/{content_id}/comments",
        _data_page(lambda item: item),
        query={"page": None if page is None else str(page)},
    )
