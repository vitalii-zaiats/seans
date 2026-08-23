"""What there is to watch.

The rules are the television module's, and for the same reason: this is
somebody else's data, so cache what does not change often and ask once when
several people ask at the same moment.

What is *not* cached is as deliberate as what is. A catalogue page is ordered by
what changed and a search is a keystroke — holding either would answer today's
question with yesterday's answer. A title is not cached because a series lists
every season and fills in one, so a held answer would pin everybody to the
season the first caller happened to want.
"""

from collections.abc import Awaitable, Sequence
from dataclasses import dataclass

from kinostrain import (
    AsyncKinostrainApi,
    CatalogFilters,
    ContentCard,
    ContentDetails,
    ContentType,
    Page,
    Person,
    SearchResult,
)
from kinostrain import HTTPError as UpstreamHTTPError
from kinostrain import NetworkError as UpstreamNetworkError

from api.core.cache import Cache
from api.errors import NotFound, Upstream

#: The one answer that is the same for everybody and changes when a genre is
#: added. Keyed by nothing, because there is nothing to key it by.
FILTERS = "filters"

#: A home rail, by name and section — `("trending", "movie")`.
type RailKey = tuple[str, str | None]


@dataclass(slots=True)
class CatalogueService:
    client: AsyncKinostrainApi
    filters: Cache[str, CatalogFilters]
    rails: Cache[RailKey, tuple[ContentCard, ...]]

    async def catalog(
        self,
        *,
        type: ContentType | None = None,
        page: int | None = None,
        genres: Sequence[str] | None = None,
        year: str | None = None,
    ) -> Page[ContentCard]:
        """A page of the catalogue."""
        return await self._guard(
            self.client.catalog(type=type, page=page, genres=genres, year=year)
        )

    async def catalog_filters(self) -> CatalogFilters:
        """Genres and year buckets per section. Static enough to hold."""
        return await self.filters.through(
            FILTERS, lambda: self._guard(self.client.catalog_filters())
        )

    async def trending(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """A home rail. Every box asks for the same one on every start."""
        return await self.rails.through(
            ("trending", type.slug if type else None),
            lambda: self._guard(self.client.trending(type=type)),
        )

    async def slider(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """The hero row, with trailers and age ratings filled in."""
        return await self.rails.through(
            ("slider", type.slug if type else None),
            lambda: self._guard(self.client.slider(type=type)),
        )

    async def search(self, query: str, *, limit: int | None = None) -> tuple[SearchResult, ...]:
        """Anything under two characters never leaves the client, which is what
        makes this safe to call on every keystroke."""
        return await self._guard(self.client.search(query, limit=limit))

    async def cards(self, slugs: Sequence[str]) -> tuple[ContentCard, ...]:
        """Cards for several slugs in one round trip.

        What a stored watchlist renders from, and what "continue watching" asks
        for. Not cached: the rows it feeds are per-person, and the answer is one
        request rather than one per title, which is the saving that matters.
        """
        if not slugs:
            return ()
        return await self._guard(self.client.cards(slugs))

    async def persons(self, *, page: int | None = None) -> Page[Person]:
        return await self._guard(self.client.persons(page=page))

    async def content(self, slug: str, *, season: int | None = None) -> ContentDetails:
        """One title in full.

        A slug nobody has is a `404` here rather than a `502`: the request was
        fine and so was upstream — the title simply is not there.
        """
        try:
            return await self.client.content(slug, season=season)
        except UpstreamHTTPError as exc:
            if exc.is_not_found:
                raise NotFound(f"no title {slug!r}") from exc
            raise Upstream(_failed(exc)) from exc
        except UpstreamNetworkError as exc:
            raise Upstream(_failed(exc)) from exc

    async def _guard[T](self, work: Awaitable[T]) -> T:
        """Somebody else's failure, said as ours.

        One place rather than nine `try` blocks — and a `502` rather than a
        `500`, because a `500` claims the fault is here when it is not.
        """
        try:
            return await work
        except (UpstreamHTTPError, UpstreamNetworkError) as exc:
            raise Upstream(_failed(exc)) from exc


def _failed(exc: Exception) -> str:
    return f"kinostrain could not be read: {exc}"
