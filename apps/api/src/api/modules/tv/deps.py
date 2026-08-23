"""Wiring for television — and the things that have to outlive a request.

The client, both caches and the throttle are module-level for the same reason
the remote's bus is: a cache rebuilt per request caches nothing, and a limiter
rebuilt per request limits nothing.

One device identity for the whole instance. To sweet.tv that is a single box
opening every stream we hand out, which is fine at this size and would not be at
a larger one — the fix, when it comes, is to pass each install's own uuid rather
than to invent more of them here.
"""

from datetime import date
from typing import Annotated

from fastapi import Depends, Request
from sweet_tv import AsyncSweetTv, Catalogue, Device, Schedule

from api.core.cache import Cache
from api.core.throttle import Throttle
from api.modules.stream.playlist import proxied
from api.modules.tv.ports import Relay
from api.modules.tv.service import STREAM_BURST, STREAMS_PER_SECOND, TvService
from api.settings import settings

CLIENT = AsyncSweetTv(device=Device(uuid=settings.sweet_tv_uuid))
CATALOGUE: Cache[str, Catalogue] = Cache(ttl=settings.tv_catalogue_ttl)
SCHEDULES: Cache[tuple[int, date], Schedule] = Cache(ttl=settings.tv_schedule_ttl)
THROTTLE: Throttle[str] = Throttle(rate=STREAMS_PER_SECOND, burst=STREAM_BURST)


def tv_service() -> TvService:
    return TvService(CLIENT, CATALOGUE, SCHEDULES, THROTTLE)


Tv = Annotated[TvService, Depends(tv_service)]


def relay() -> Relay:
    """Which relay satisfies the port. The only line in this module that knows."""
    return proxied


Through = Annotated[Relay, Depends(relay)]


def caller(request: Request) -> str:
    """Who to count the stream against.

    An address, not an identity: these channels are free and asking for one
    would shut anonymous boxes out of television altogether. Behind a proxy this
    is the proxy unless it is configured to say otherwise, which is a deployment
    question rather than one for this file.
    """
    return request.client.host if request.client else "unknown"


Caller = Annotated[str, Depends(caller)]
