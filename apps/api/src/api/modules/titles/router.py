"""The merged catalogue.

Open, like `catalogue/` and for the same reason: browsing is not something to
require an account for.

The paths deliberately do not mirror an upstream — there is no upstream here.
`/titles/keys` is the one a remote calls on every press.
"""

from typing import Annotated

from fastapi import APIRouter, Query

from api.modules.titles.deps import Titles
from api.modules.titles.schemas import DetailsOut, TitleList

router = APIRouter(prefix="/titles", tags=["titles"])


@router.get("/keys", response_model=TitleList)
async def by_keys(
    titles: Titles,
    keys: Annotated[str, Query(min_length=1, max_length=32, description="Digits, as pressed")],
    limit: Annotated[int, Query(ge=1, le=50)] = 12,
) -> TitleList:
    """Titles a telephone keypad finds.

    `keys` is what the remote's number pad produced — `2647454` for Ґріфіни,
    `326459` for Family Guy, and both answer with the same title. Every word
    start is indexed, so `489` finds "Family Guy" without the first word and
    `0` is never needed as a separator.

    Under two digits this refuses rather than answers: one digit selects a
    third of the catalogue and narrows nothing.
    """
    return TitleList.of(await titles.by_keys(keys, limit=limit))


@router.get("/{slug}", response_model=DetailsOut)
async def details(titles: Titles, slug: str) -> DetailsOut:
    """One title, with every source that has it and everything that plays it.

    `sources[].evidence` says what made two catalogues' rows into one title —
    `imdb+ashdi+name` when all three keys agreed, `name` when only the spelling
    did, `sole` when nothing else in either catalogue is this film.
    """
    return DetailsOut.of(await titles.watchable(slug))
