"""Wiring for watch-together — and the process-wide bus.

The bus and the throttle are module-level objects for the reason the remote's
are: an in-memory bus *is* process-wide, and handing each request its own would
mean a position published on one and listened for on another. The day this runs
as more than one process, the composition root builds a Redis one here and
nothing else changes.

Note which of the two credentials this file reads. `Authorization` says who you
are and is optional — a room admits somebody who has never said. `X-Room-Token`
says which *seat* you are, and is the only thing that grants anything. A header
rather than a query parameter because a token in a query string lands in every
access log on the way; the browser's `EventSource` cannot send one either way,
so a web client of these streams needs the same `fetch` reader the remote's
already needed.
"""

from typing import Annotated

from fastapi import Depends, Request

from api.core.bus import MemoryBus
from api.core.deps import DB
from api.core.throttle import Throttle
from api.errors import Unauthorized
from api.modules.together.events import RoomEvent
from api.modules.together.models import Member
from api.modules.together.service import REPORT_BURST, REPORTS_PER_SECOND, TogetherService

BUS: MemoryBus[int, RoomEvent] = MemoryBus()
# Same reason as the bus: a limiter rebuilt per request remembers nothing.
REPORTS: Throttle[int] = Throttle(rate=REPORTS_PER_SECOND, burst=REPORT_BURST)


def together_service(session: DB) -> TogetherService:
    return TogetherService(session, BUS, REPORTS)


Together = Annotated[TogetherService, Depends(together_service)]


def room_token(request: Request) -> str | None:
    return (request.headers.get("x-room-token") or "").strip() or None


RoomToken = Annotated[str | None, Depends(room_token)]


async def seat(token: RoomToken, together: Together) -> Member | None:
    """The seat this request is holding, or nobody.

    `None` covers a missing token, a token that was never one, a seat that was
    given up and a room that is over. Deliberately the same answer: any of them
    means "you are not in that room", and the differences are only useful to
    somebody probing.
    """
    return await together.seat_for(token)


MaybeSeat = Annotated[Member | None, Depends(seat)]


async def current_seat(found: MaybeSeat) -> Member:
    if found is None:
        raise Unauthorized("this needs a seat in the room")
    return found


CurrentSeat = Annotated[Member, Depends(current_seat)]
