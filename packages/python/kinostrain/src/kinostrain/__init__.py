"""Typed Python client for the public kinostrain.com content API.

Start from `KinostrainApi` (or `AsyncKinostrainApi`); every response is mapped
onto the models exported below. The client performs no I/O of its own — it
talks to a `Transport`, and `kinostrain.transports.httpx` is the one it builds
when you do not supply another.

    from kinostrain import ContentType, KinostrainApi

    with KinostrainApi() as api:
        for card in api.catalog(type=ContentType.MOVIE).items:
            print(card.name, card.year_label)
"""

from kinostrain.client import (
    DEFAULT_BASE_URL,
    DEFAULT_TIMEOUT,
    SITE_HEADERS,
    AsyncKinostrainApi,
    KinostrainApi,
)
from kinostrain.errors import HTTPError, KinostrainError, NetworkError, SerializationError
from kinostrain.jsonread import JsonMap
from kinostrain.models import (
    CatalogFilters,
    ContentCard,
    ContentDetails,
    ContentType,
    ContentTypeFilters,
    Credit,
    Episode,
    Franchise,
    FranchiseItem,
    Gender,
    Genre,
    NameSpan,
    Page,
    PageMeta,
    Person,
    PlayerSource,
    Providers,
    ReadySeason,
    SearchResult,
    Season,
    SeasonFrame,
    YearOption,
)
from kinostrain.transport import AsyncTransport, Request, Response, Transport

__version__ = "0.1.0"

__all__ = [
    "DEFAULT_BASE_URL",
    "DEFAULT_TIMEOUT",
    "SITE_HEADERS",
    "AsyncKinostrainApi",
    "AsyncTransport",
    "CatalogFilters",
    "ContentCard",
    "ContentDetails",
    "ContentType",
    "ContentTypeFilters",
    "Credit",
    "Episode",
    "Franchise",
    "FranchiseItem",
    "Gender",
    "Genre",
    "HTTPError",
    "JsonMap",
    "KinostrainApi",
    "KinostrainError",
    "NameSpan",
    "NetworkError",
    "Page",
    "PageMeta",
    "Person",
    "PlayerSource",
    "Providers",
    "ReadySeason",
    "Request",
    "Response",
    "SearchResult",
    "Season",
    "SeasonFrame",
    "SerializationError",
    "Transport",
    "YearOption",
    "__version__",
]
