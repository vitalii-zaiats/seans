"""What a crawl produces. Sources fill these in, sinks consume them."""

from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field, replace
from typing import Any, TypedDict, cast


class ItemPayload(TypedDict):
    """The flat JSON shape sinks store.

    Source-specific fields ride along *beside* these rather than nested under a
    key of their own, because that's what the sinks and the seeder read.
    """

    source: str
    title: str
    url: str
    poster: str | None


class PagePayload(TypedDict):
    source: str
    page: int
    url: str
    error: str | None
    items: list[ItemPayload]


@dataclass(frozen=True, slots=True)
class Item:
    title: str
    url: str
    poster: str | None = None
    source: str = ""
    # Anything a particular site offers that others don't (kind, rating, year...).
    # Open by nature — each source decides — so it stays a mapping.
    extra: Mapping[str, Any] = field(default_factory=dict)

    def with_details(self, other: "Item") -> "Item":
        """This item as its own page describes it.

        The page wins wherever it has an answer — its poster is the full-size one,
        its title the untruncated one — and the listing's URL stays the item's
        identity, because that's what the sinks have already stored it under.
        """
        return replace(
            self,
            title=other.title or self.title,
            poster=other.poster or self.poster,
            extra={**self.extra, **other.extra},
        )

    def with_error(self, error: str) -> "Item":
        """The item as it stands, saying why it isn't more than that."""
        return replace(self, extra={**self.extra, "error": error})

    def to_dict(self) -> ItemPayload:
        payload = ItemPayload(
            source=self.source, title=self.title, url=self.url, poster=self.poster
        )
        if not self.extra:
            return payload
        # The extras are merged flat; the cast says so out loud.
        return cast(ItemPayload, {**payload, **self.extra})


class StatsPayload(TypedDict):
    source: str
    pages: int
    failed: int
    found: int
    stored: int


@dataclass(slots=True)
class Page:
    source: str
    number: int
    url: str
    items: list[Item]
    error: str | None = None

    @classmethod
    def of(cls, source: str, number: int, url: str, items: Iterable[Item]) -> "Page":
        """A read page. Stamping the source here means no engine can forget to."""
        return cls(
            source=source,
            number=number,
            url=url,
            items=[replace(item, source=source) for item in items],
        )

    @classmethod
    def broken(cls, source: str, number: int, url: str, error: str) -> "Page":
        """A page that wouldn't load. One bad page must not end a crawl."""
        return cls(source=source, number=number, url=url, items=[], error=error)

    def to_dict(self) -> PagePayload:
        return PagePayload(
            source=self.source,
            page=self.number,
            url=self.url,
            error=self.error,
            items=[item.to_dict() for item in self.items],
        )


@dataclass(slots=True)
class Stats:
    """What a drained crawl amounted to."""

    source: str
    pages: int = 0
    failed: int = 0
    found: int = 0
    stored: int = 0

    def to_dict(self) -> StatsPayload:
        return StatsPayload(
            source=self.source,
            pages=self.pages,
            failed=self.failed,
            found=self.found,
            stored=self.stored,
        )
