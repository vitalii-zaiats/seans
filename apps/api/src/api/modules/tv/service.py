"""What is on the free channels, and how to play it.

Everything here is somebody else's data, so the rules are about being a decent
guest: cache what does not change often, ask once when several people ask at the
same moment, and put a ceiling on the one call that costs the other side real
work.
"""

from dataclasses import dataclass
from datetime import date

from sweet_tv import AsyncSweetTv, Catalogue, Channel, Refused, Schedule, Stream
from sweet_tv import HTTPError as UpstreamHTTPError
from sweet_tv import NetworkError as UpstreamNetworkError

from api.core.cache import Cache
from api.core.throttle import Throttle
from api.errors import Forbidden, NotFound, Upstream

#: Opening a stream costs the other side a session. A person changing channels
#: presses this a few times a minute; anything faster is a script.
STREAMS_PER_SECOND = 0.5
STREAM_BURST = 6.0

#: One key, because there is one list. A `Cache` rather than a plain attribute
#: so the expiry and the single-flight are the same code as the schedule's.
CATALOGUE = "catalogue"


@dataclass(slots=True)
class TvService:
    client: AsyncSweetTv
    catalogue: Cache[str, Catalogue]
    schedules: Cache[tuple[int, date], Schedule]
    throttle: Throttle[str]

    async def channels(self) -> Catalogue:
        """Every free channel, with its categories.

        The one call a browser cannot make for itself — the catalogue's host
        sends no CORS headers at all.
        """
        return await self.catalogue.through(CATALOGUE, self._fetch_channels)

    async def channel(self, channel_id: int) -> Channel:
        found = (await self.channels()).by_id(channel_id)
        if found is None:
            raise NotFound(f"no channel {channel_id}")
        return found

    async def schedule(self, channel_id: int, day: date) -> Schedule:
        """One channel's programmes for one day.

        The channel is looked up first so an unknown id is a 404 rather than an
        empty day, which reads the same to a client and means something else
        entirely.
        """
        await self.channel(channel_id)
        return await self.schedules.through(
            (channel_id, day), lambda: self._fetch_schedule(channel_id, day)
        )

    async def open_stream(self, channel_id: int, *, caller: str) -> Stream:
        """A lease on the stream, for a caller identified only by address.

        Not cached, and it must not be: what comes back carries a session that
        goes stale in minutes, and handing two viewers the same one is how both
        of them get dropped.
        """
        if not self.throttle.allow(caller):
            raise Forbidden("too many streams; slow down")

        await self.channel(channel_id)
        try:
            return await self.client.open_stream(channel_id)
        except Refused as exc:
            # Everything on the free list opens. A refusal here means the list
            # and the service disagree, which is worth saying plainly.
            raise Forbidden(str(exc)) from exc
        except (UpstreamHTTPError, UpstreamNetworkError) as exc:
            raise Upstream(f"sweet.tv could not open channel {channel_id}: {exc}") from exc

    async def _fetch_channels(self) -> Catalogue:
        try:
            return await self.client.channels()
        except (UpstreamHTTPError, UpstreamNetworkError) as exc:
            raise Upstream(f"sweet.tv could not be read: {exc}") from exc

    async def _fetch_schedule(self, channel_id: int, day: date) -> Schedule:
        try:
            return await self.client.schedule(channel_id, day)
        except UpstreamHTTPError as exc:
            # A day nobody published is a 404 upstream, and an empty day here —
            # a channel simply has no schedule that far out.
            if exc.is_not_found:
                return Schedule()
            raise Upstream(f"sweet.tv could not be read: {exc}") from exc
        except UpstreamNetworkError as exc:
            raise Upstream(f"sweet.tv could not be read: {exc}") from exc
