"""The admin dashboard's two endpoints.

Both are `Admin`, from the accounts module's dependencies — reading how many
copies of the app exist, and on what, is not a thing a signed-in stranger gets
to do.

Split in two because they change at different rates. The overview re-measures a
month and is asked for once a minute at most; the table under it is paged and
searched, and re-running a month's worth of aggregates on every keystroke would
be the obvious way to make a dashboard that nobody leaves open.
"""

from typing import Annotated

from fastapi import APIRouter, Query

from api.modules.accounts.deps import Admin
from api.modules.stats.deps import Stats
from api.modules.stats.ports import Platform
from api.modules.stats.schemas import OverviewOut, RecordOut, RecordPage

router = APIRouter(prefix="/admin/stats", tags=["stats"])


@router.get("/installs", response_model=OverviewOut)
async def installs(
    admin: Admin,
    stats: Stats,
    days: Annotated[int, Query(ge=1, le=365, description="Window length, in whole UTC days")] = 30,
    active_days: Annotated[
        int, Query(ge=1, le=365, description="How recently an install must have launched")
    ] = 7,
    top: Annotated[int, Query(ge=1, le=50, description="Rows per breakdown")] = 8,
) -> OverviewOut:
    """Totals, a day-by-day series, and the three breakdowns, over one window."""
    return OverviewOut.of(await stats.overview(days=days, active_days=active_days, top=top))


@router.get("/installs/recent", response_model=RecordPage)
async def recent(
    admin: Admin,
    stats: Stats,
    limit: Annotated[int, Query(ge=1, le=200)] = 25,
    offset: Annotated[int, Query(ge=0)] = 0,
    platform: Platform | None = None,
    q: Annotated[
        str | None,
        Query(max_length=128, description="A full install uuid, or part of a version or vendor"),
    ] = None,
) -> RecordPage:
    """The installs themselves, most recently seen first."""
    found = await stats.recent(limit=limit, offset=offset, platform=platform, query=q)
    return RecordPage(
        items=[RecordOut.of(record) for record in found.items],
        total=found.total,
        limit=limit,
        offset=offset,
    )
