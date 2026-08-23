"""Watching the same film in more than one place.

Seven endpoints, and one asymmetry that is the whole design: the host writes and
everybody else reads. There is no way for a member to move the film, so there is
no way for two players to argue about where it is.

Two credentials, doing two different jobs. `Authorization` is optional and says
who you are — it buys a name on the roster and a way back into your own seat
after a reload. `X-Room-Token` says which seat you are, and is what actually
grants anything: it is how a room admits somebody who has told us nothing at all.

Nothing carries an SSE `id:`, for the same reason nothing in the remote does.
Replaying a position is exactly wrong — a member whose Wi-Fi blinked must not be
told where the film was a minute ago. What they get instead is the current state
the moment the stream opens, which is resumption for the half where it makes
sense.
"""

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse

from api.core import sse
from api.errors import NotFound
from api.modules.accounts.deps import Viewer
from api.modules.together.deps import CurrentSeat, MaybeSeat, Together
from api.modules.together.events import Closed, Presence, Showing
from api.modules.together.models import Member
from api.modules.together.schemas import (
    ClosedOut,
    JoinRequest,
    OpenRequest,
    PresenceOut,
    ReportRequest,
    RoomOut,
    RoomPage,
    SeatOut,
    ShowingOut,
)
from api.modules.together.service import TogetherService, snapshot

router = APIRouter(prefix="/rooms", tags=["together"])


@router.get("", response_model=RoomPage)
async def listing(
    together: Together,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> RoomPage:
    """The public rooms, busiest-first, with what is playing in each.

    No identity needed to read it: a public room is an invitation, and an
    invitation nobody can see is not one.
    """
    page = await together.listing(limit=limit, offset=offset)
    return RoomPage(
        total=page.total,
        limit=limit,
        offset=offset,
        items=[RoomOut.of(room) for room in page.items],
    )


@router.post("", response_model=SeatOut, status_code=201)
async def open_room(body: OpenRequest, user: Viewer, together: Together) -> SeatOut:
    """Start a room and take the host's seat in it.

    `user` is whoever the request turned out to belong to, and `None` is a
    supported answer — this deliberately does not mint a guest on the way, the
    way nothing else in this API does either.
    """
    return SeatOut.of(
        await together.open_room(
            title=body.title,
            public=body.is_public,
            host=user,
            display_name=body.display_name,
            media=None if body.media is None else body.media.media(),
        )
    )


@router.post("/join", response_model=SeatOut, status_code=201)
async def join(body: JoinRequest, user: Viewer, together: Together) -> SeatOut:
    """Take a seat, by code.

    Somebody signed in who is already in this room comes back to the seat they
    had — the host's, if that is what it was. Everybody else gets a new one.
    """
    return SeatOut.of(await together.join(body.code, person=user, display_name=body.display_name))


@router.get("/{public_id}", response_model=RoomOut)
async def room(public_id: str, seat: MaybeSeat, together: Together) -> RoomOut:
    """One room — a title and a poster, for somebody deciding whether to join.

    Answered for a private room too. Whoever asks had to be told the id by
    somebody, and what comes back has no way in attached: the code is withheld
    unless they are already seated.
    """
    return RoomOut.of(await together.room_for(public_id, seat=seat))


@router.post("/{public_id}/state", response_model=ShowingOut)
async def report(
    public_id: str, body: ReportRequest, seat: CurrentSeat, together: Together
) -> ShowingOut:
    """The host saying where the film is. Only the host may.

    Written down and published in one go: the row is what a latecomer and the
    listing read, the stream is what everybody already watching hears.
    """
    _in_room(seat, public_id)
    return ShowingOut.of(
        await together.report(
            seat,
            media=None if body.media is None else body.media.media(),
            position=body.position,
            paused=body.paused,
        )
    )


@router.post("/{public_id}/leave", status_code=204)
async def leave(public_id: str, seat: CurrentSeat, together: Together) -> None:
    """Give the seat up. The host leaving ends the room for everybody."""
    _in_room(seat, public_id)
    await together.leave(seat)


@router.delete("/{public_id}", status_code=204)
async def close(public_id: str, seat: CurrentSeat, together: Together) -> None:
    """That's the end of it. Everybody with a stream open is told, once."""
    _in_room(seat, public_id)
    await together.close(seat)


@router.get("/{public_id}/events")
async def watch(public_id: str, seat: CurrentSeat, together: Together) -> StreamingResponse:
    """Everything the room says, for as long as it says anything.

        state    where the film is, and what it is
        members  who is here
        closed   the last thing this stream will ever say

    The reading happens here rather than inside the generator, and on purpose: a
    session held open for the life of an SSE stream is a database connection
    held open for the life of an SSE stream, and there are as many of those as
    there are people watching. Everything below the `return` runs on the bus
    alone.
    """
    _in_room(seat, public_id)
    return _stream(await _open(together, seat))


def _in_room(seat: Member, public_id: str) -> None:
    """The seat and the path have to agree.

    The token already says which room this is, so the id in the path is
    redundant — which is exactly why it is checked rather than ignored: a client
    that muddles two rooms should hear about it here, not by driving the wrong
    film.
    """
    if seat.room.public_id != public_id:
        raise NotFound("no such room")


def _stream(source: AsyncIterator[bytes]) -> StreamingResponse:
    return StreamingResponse(source, media_type="text/event-stream", headers=sse.HEADERS)


async def _open(together: TogetherService, seat: Member) -> AsyncIterator[bytes]:
    """Everything this stream needs from the database, read before it starts.

    Split out so that the generator below touches nothing but the bus — and so a
    test can drive it, since `ASGITransport` never returns from a `stream()`
    whose body is endless by design.
    """
    room = seat.room
    opening = ShowingOut.of(snapshot(room)).model_dump_json()
    roster = await together.presence(room)
    await together.touch(seat)
    return _events(together, room.id, opening, roster)


async def _events(
    together: TogetherService, room_id: int, opening: str, roster: Presence
) -> AsyncIterator[bytes]:
    async with together.bus.listen(room_id) as events:
        yield sse.frame("state", opening)
        # Published rather than written straight to this stream, so that the
        # room learns somebody arrived at the same moment the arrival does — and
        # published *after* `listen`, so the count includes this stream.
        await together.bus.publish(
            room_id, Presence(watching=together.bus.listeners(room_id), members=roster.members)
        )
        yield sse.comment("open")

        async for event in sse.with_keepalive(events):
            if event is None:
                yield sse.comment("ping")
            elif isinstance(event, Showing):
                yield sse.frame("state", ShowingOut.of(event).model_dump_json())
            elif isinstance(event, Presence):
                yield sse.frame("members", PresenceOut.of(event).model_dump_json())
            elif isinstance(event, Closed):
                yield sse.frame("closed", ClosedOut(reason=event.reason).model_dump_json())
                # Nothing else is coming. Ending the body rather than idling is
                # also what stops an `EventSource` reconnecting forever: its
                # next attempt is answered 401, because the seat is in a room
                # that no longer exists.
                return
