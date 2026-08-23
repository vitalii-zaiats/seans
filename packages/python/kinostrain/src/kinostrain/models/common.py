"""Small shapes that turn up all over the API: genres, year buckets, pages."""

from collections.abc import Callable, Iterator
from dataclasses import dataclass

from kinostrain.errors import SerializationError
from kinostrain.jsonread import JsonMap, list_of, map_or_none, require_int, require_str


@dataclass(frozen=True, slots=True)
class Genre:
    """A genre, as it appears in cards, details and `/catalog/filters`."""

    #: Localised label, e.g. `Бойовик`.
    name: str
    #: Query value, e.g. `bojovik` — what `/catalog?genres=` expects.
    slug: str

    @classmethod
    def from_json(cls, json: JsonMap) -> "Genre":
        return cls(
            name=require_str(json, "name", owner="Genre"),
            slug=require_str(json, "slug", owner="Genre"),
        )


@dataclass(frozen=True, slots=True)
class YearOption:
    """A selectable value for `/catalog?year=`.

    The API mixes single years (`2024`) with ranges (`2006-2010`, `2021-2026`)
    and one open-ended bucket (`2000-1900`), so the value stays a string.
    """

    name: str
    slug: str

    @classmethod
    def from_json(cls, json: JsonMap) -> "YearOption":
        return cls(
            name=require_str(json, "name", owner="YearOption"),
            slug=require_str(json, "slug", owner="YearOption"),
        )

    @property
    def is_range(self) -> bool:
        """Whether the option covers several years rather than a single one."""
        return "-" in self.slug


@dataclass(frozen=True, slots=True)
class PageMeta:
    """The `meta` block returned by every paginated endpoint."""

    #: 1-based index of the returned page.
    page: int
    per_page: int
    #: Items across all pages, not on this one.
    total: int
    total_pages: int

    @classmethod
    def from_json(cls, json: JsonMap) -> "PageMeta":
        return cls(
            page=require_int(json, "page", owner="PageMeta"),
            per_page=require_int(json, "perPage", owner="PageMeta"),
            total=require_int(json, "total", owner="PageMeta"),
            total_pages=require_int(json, "totalPages", owner="PageMeta"),
        )

    @property
    def has_next_page(self) -> bool:
        return self.page < self.total_pages

    @property
    def next_page(self) -> int | None:
        """The page to ask for next, or `None` on the last one."""
        return self.page + 1 if self.has_next_page else None

    def __str__(self) -> str:
        return f"page {self.page}/{self.total_pages}, {self.total} total"


@dataclass(frozen=True)
class Page[T]:
    """A `{"data": [...], "meta": {...}}` response."""

    items: tuple[T, ...]
    meta: PageMeta

    @classmethod
    def from_json(cls, json: JsonMap, parse: Callable[[JsonMap], T]) -> "Page[T]":
        meta = map_or_none(json, "meta")
        if meta is None:
            raise SerializationError("expected a `meta` object on a paginated response")
        return cls(items=list_of(json, "data", parse), meta=PageMeta.from_json(meta))

    def __iter__(self) -> Iterator[T]:
        return iter(self.items)

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, index: int) -> T:
        return self.items[index]

    @property
    def has_next_page(self) -> bool:
        """Passthrough for `meta.has_next_page`."""
        return self.meta.has_next_page
