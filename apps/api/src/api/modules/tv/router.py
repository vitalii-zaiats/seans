"""Free-to-air television.

Open, deliberately. These are free channels and requiring an account would shut
anonymous boxes out of them — so what stands between this and abuse is a cache
on the reads and a ceiling on the one call that costs the other side work.
"""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query

from api.modules.tv.deps import Caller, Through, Tv
from api.modules.tv.schemas import ChannelList, ScheduleOut, StreamOut

router = APIRouter(prefix="/tv", tags=["tv"])


@router.get("/channels", response_model=ChannelList)
async def channels(tv: Tv) -> ChannelList:
    """Every free channel, with its categories.

    Cached: the list changes when a channel is added, not per viewer. Each entry
    already carries what is on right now, so a grid needs no request per row.
    """
    return ChannelList.of(await tv.channels())


@router.get("/channels/{channel_id}/schedule", response_model=ScheduleOut)
async def schedule(
    channel_id: int,
    tv: Tv,
    day: Annotated[date | None, Query(description="Defaults to today")] = None,
) -> ScheduleOut:
    """One channel's programmes for one day.

    A day upstream never published comes back empty rather than as an error — a
    channel simply has no schedule that far out.
    """
    wanted = day or date.today()
    return ScheduleOut.of(channel_id, wanted, await tv.schedule(channel_id, wanted))


@router.post("/channels/{channel_id}/stream", response_model=StreamOut)
async def stream(
    channel_id: int,
    tv: Tv,
    caller: Caller,
    through: Through,
    use_proxy: Annotated[
        bool,
        Query(description="Point the addresses at `/stream` instead of the host itself"),
    ] = False,
) -> StreamOut:
    """A playable address for a channel.

    A lease rather than an address: it carries a session and goes stale after
    `refresh_in`. Ask again rather than storing it.

    **`use_proxy` is for browsers and only for browsers.** The stitched playlist
    comes from a host that does not answer `access-control-allow-origin`, so a
    page cannot read it; set the flag and every address here comes back pointing
    at `/stream`, which can. A native build — Android, a box, a desktop — has no
    such rule and should leave it off: the video then goes host-to-viewer
    instead of through us, which is faster and costs us nothing.
    """
    return StreamOut.of(
        channel_id,
        await tv.open_stream(channel_id, caller=caller),
        through=through if use_proxy else None,
    )
