"""The `/catalog/filters` directory: what can be filtered on, per section."""

from collections.abc import Mapping
from dataclasses import dataclass, field

from kinostrain.jsonread import JsonMap, int_or_none, list_of, map_or_none
from kinostrain.models.common import Genre, YearOption
from kinostrain.models.enums import ContentType


@dataclass(frozen=True, slots=True)
class ContentTypeFilters:
    """The genre and year options available for one `ContentType`."""

    #: Genres the site surfaces up front.
    popular_genres: tuple[Genre, ...] = ()
    #: The long tail, behind a "more" toggle on the website.
    other_genres: tuple[Genre, ...] = ()
    years: tuple[YearOption, ...] = ()
    #: How many titles this section holds in total.
    total_count: int = 0

    @classmethod
    def from_json(cls, json: JsonMap) -> "ContentTypeFilters":
        genres = map_or_none(json, "genres") or {}
        return cls(
            popular_genres=list_of(genres, "popular", Genre.from_json),
            other_genres=list_of(genres, "other", Genre.from_json),
            years=list_of(json, "years", YearOption.from_json),
            total_count=int_or_none(json, "totalCount") or 0,
        )

    @property
    def all_genres(self) -> tuple[Genre, ...]:
        """Popular first, then the rest."""
        return self.popular_genres + self.other_genres

    def genre_by_slug(self, slug: str) -> Genre | None:
        """Looks a genre up across both groups."""
        return next((genre for genre in self.all_genres if genre.slug == slug), None)


@dataclass(frozen=True, slots=True)
class CatalogFilters:
    """The whole response: one `ContentTypeFilters` per section."""

    by_type: Mapping[ContentType, ContentTypeFilters] = field(default_factory=dict)
    #: Section keys the server sent that this package does not model yet. Empty
    #: in normal operation; non-empty means the API grew a new section.
    unknown_type_keys: tuple[str, ...] = ()

    @classmethod
    def from_json(cls, json: JsonMap) -> "CatalogFilters":
        by_type: dict[ContentType, ContentTypeFilters] = {}
        unknown: list[str] = []
        for key, value in json.items():
            if not isinstance(value, Mapping):
                continue
            section = ContentType.try_parse(key)
            if section is None:
                unknown.append(key)
                continue
            by_type[section] = ContentTypeFilters.from_json(value)
        return cls(by_type=by_type, unknown_type_keys=tuple(unknown))

    def get(self, section: ContentType) -> ContentTypeFilters | None:
        """Filters for `section`, or `None` if the response omitted it."""
        return self.by_type.get(section)

    def __getitem__(self, section: ContentType) -> ContentTypeFilters:
        return self.by_type[section]

    def __contains__(self, section: ContentType) -> bool:
        return section in self.by_type

    @property
    def total_count(self) -> int:
        """Titles across all sections."""
        return sum(filters.total_count for filters in self.by_type.values())
