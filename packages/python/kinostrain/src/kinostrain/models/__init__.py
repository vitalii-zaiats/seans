"""Every shape the API returns, one module per area."""

from kinostrain.models.card import ContentCard, ReadySeason
from kinostrain.models.common import Genre, Page, PageMeta, YearOption
from kinostrain.models.details import ContentDetails
from kinostrain.models.enums import ContentType, Gender
from kinostrain.models.filters import CatalogFilters, ContentTypeFilters
from kinostrain.models.franchise import Franchise, FranchiseItem
from kinostrain.models.people import Credit, Person
from kinostrain.models.search import NameSpan, SearchResult
from kinostrain.models.season import Episode, PlayerSource, Providers, Season, SeasonFrame

__all__ = [
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
    "NameSpan",
    "Page",
    "PageMeta",
    "Person",
    "PlayerSource",
    "Providers",
    "ReadySeason",
    "SearchResult",
    "Season",
    "SeasonFrame",
    "YearOption",
]
