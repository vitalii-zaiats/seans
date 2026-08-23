"""The catalogue.

Open, like the television module and for the same reason: this is a public
catalogue, and requiring an account would shut anonymous boxes out of browsing.

Every path here mirrors one upstream. That is deliberate — this is a proxy with
a cache, not a redesign, and a client that knows the upstream's shape can read
this one without a translation table.
"""

from typing import Annotated

from fastapi import APIRouter, Body, Query
from kinostrain import ContentType

from api.modules.catalogue.deps import Catalogue
from api.modules.catalogue.schemas import (
    CardList,
    CardPage,
    DetailsOut,
    FiltersOut,
    HitList,
    PersonPage,
)

router = APIRouter(prefix="/catalogue", tags=["catalogue"])


@router.get("/content", response_model=CardPage)
async def catalog(
    catalogue: Catalogue,
    type: ContentType | None = None,
    page: Annotated[int | None, Query(ge=1)] = None,
    genres: Annotated[list[str] | None, Query(description="Slugs, not names")] = None,
    year: Annotated[str | None, Query(description="A slug: 2024, or 2006-2010")] = None,
) -> CardPage:
    """A page of the catalogue.

    `genres` and `year` take slugs from `/catalogue/filters`, not display names.
    Never cached: the ordering is by what changed, so a held page would show
    somebody yesterday's answer.
    """
    return CardPage.of(await catalogue.catalog(type=type, page=page, genres=genres, year=year))


@router.get("/filters", response_model=FiltersOut)
async def filters(catalogue: Catalogue) -> FiltersOut:
    """Genres and year buckets per section, with per-section counts.

    Cached: it changes when a genre is added, which is not often.
    """
    return FiltersOut.of(await catalogue.catalog_filters())


@router.get("/trending", response_model=CardList)
async def trending(catalogue: Catalogue, type: ContentType | None = None) -> CardList:
    """A home rail, richer than a catalogue card. Not paginated."""
    return CardList.of(await catalogue.trending(type=type))


@router.get("/slider", response_model=CardList)
async def slider(catalogue: Catalogue, type: ContentType | None = None) -> CardList:
    """The hero row, with trailer ids and age ratings filled in."""
    return CardList.of(await catalogue.slider(type=type))


@router.get("/search", response_model=HitList)
async def search(
    catalogue: Catalogue,
    q: Annotated[str, Query(min_length=1, max_length=200)],
    limit: Annotated[int | None, Query(ge=1, le=50)] = None,
) -> HitList:
    """Titles matching `q`.

    Anything under two characters comes back empty without a round trip, which
    is what makes this safe to call on every keystroke.
    """
    return HitList.of(await catalogue.search(q, limit=limit))


@router.post("/cards", response_model=CardList)
async def cards(
    catalogue: Catalogue,
    slugs: Annotated[list[str], Body(embed=True, max_length=200)],
) -> CardList:
    """Cards for several slugs at once.

    A `POST` because the list can be long and a stored watchlist is not
    something to put in a URL. Neither the order nor an entry for every slug is
    guaranteed — upstream answers with what it has.
    """
    return CardList.of(await catalogue.cards(slugs))


@router.get("/persons", response_model=PersonPage)
async def persons(
    catalogue: Catalogue, page: Annotated[int | None, Query(ge=1)] = None
) -> PersonPage:
    """The directory of actors and directors."""
    return PersonPage.of(await catalogue.persons(page=page))


@router.get("/content/{slug}", response_model=DetailsOut)
async def content(
    catalogue: Catalogue,
    slug: str,
    season: Annotated[int | None, Query(ge=1)] = None,
) -> DetailsOut:
    """One title in full.

    A series lists **every** season but fills in the episodes and players of
    one. Pass `season` to fill in a different one — the rest come back empty
    either way, and `is_loaded` is what tells "not fetched yet" from "nothing to
    watch".
    """
    return DetailsOut.of(await catalogue.content(slug, season=season))
