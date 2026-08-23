"""A collection a title belongs to."""

from dataclasses import dataclass

from kinostrain.jsonread import (
    JsonMap,
    bool_or,
    float_or_none,
    int_or_none,
    list_of,
    require_str,
    str_or_none,
)


@dataclass(frozen=True, slots=True)
class FranchiseItem:
    """One entry in a franchise's ordered list of titles."""

    name: str
    original_name: str
    slug: str
    format: str = ""
    #: `True` for the title whose detail page you are looking at.
    is_current: bool = False
    year: int | None = None
    imdb_mark: float | None = None
    poster_url: str | None = None
    #: Set when the entry is a specific season rather than a whole title.
    season_number: int | None = None
    last_url_suffix: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "FranchiseItem":
        owner = "FranchiseItem"
        return cls(
            name=require_str(json, "name", owner=owner),
            original_name=require_str(json, "originalName", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            format=str_or_none(json, "format") or "",
            is_current=bool_or(json, "isCurrent"),
            year=int_or_none(json, "year"),
            imdb_mark=float_or_none(json, "imdbMark"),
            poster_url=str_or_none(json, "posterUrl"),
            season_number=int_or_none(json, "seasonNumber"),
            last_url_suffix=str_or_none(json, "lastUrlSuffix"),
        )


@dataclass(frozen=True, slots=True)
class Franchise:
    """A collection a title belongs to, with its sibling titles."""

    name: str
    slug: str
    items: tuple[FranchiseItem, ...] = ()
    description: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Franchise":
        owner = "Franchise"
        return cls(
            name=require_str(json, "name", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            items=list_of(json, "items", FranchiseItem.from_json),
            description=str_or_none(json, "description"),
        )

    @property
    def current(self) -> FranchiseItem | None:
        """The entry marked `isCurrent`, if upstream flagged one."""
        return next((item for item in self.items if item.is_current), None)
