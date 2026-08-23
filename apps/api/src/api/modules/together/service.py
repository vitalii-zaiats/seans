"""Opening a room, getting into one, and keeping everybody at the same second.

Three rules hold the whole thing up.

**A seat, not a person.** Joining mints a token that stands for a place in one
room. Anonymous, guest and signed-in all get the same thing, because a room that
only admitted accounts would fail the one case it exists for — somebody sending
a friend a code. An account, when there is one, buys a name worth showing and a
way back into the same seat after a reload.

**The host is the clock.** Only the seat that opened the room may say where the
film has got to. Everybody else follows. There is no vote, no last-writer-wins
and no way for two players to argue, which is the failure every shared-playback
feature has in it somewhere.

**Nothing is replayed.** A position is about *now*. What the room is showing is
kept on its row so that a listing can be drawn and a latecomer can be told where
to seek — and it is wound forward to the moment it is handed over, because a
stale position is worse than none.
"""

import secrets
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api.core.bus import Bus
from api.core.models import utcnow
from api.core.security import new_token, token_digest
from api.core.throttle import Throttle
from api.errors import Conflict, Forbidden, Invalid, NotFound
from api.modules.together.events import (
    Closed,
    Media,
    MediaKind,
    Playback,
    Presence,
    Reason,
    RoomEvent,
    Showing,
    Watcher,
)
from api.modules.together.models import Kind, Member, Room, Seat, Visibility
from api.modules.together.ports import Person
from api.modules.together.repository import MemberRepository, RoomRepository

# The same alphabet a device link uses, and for the same reason: this is read
# off one screen and typed into another, sometimes out loud. No O/0, no I/1.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6

#: A host reports on every play, pause and seek, plus a heartbeat while it runs.
#: Ten a second is a scrub bar being dragged, not a player.
REPORTS_PER_SECOND = 4.0
REPORT_BURST = 12.0

# There is deliberately no limit on *opening* a room here. The obvious one —
# a bucket per caller address — would be a single global bucket in production:
# this app runs in a container behind nginx in another, so uvicorn does not
# trust the `X-Forwarded-For` it is sent and every request arrives from the
# proxy's address. A limit that cannot see who it is limiting is a limit on
# everybody. It belongs at the edge, where the real address is, next to the one
# `POST /auth/guest` also does not have.

#: A room nobody has touched for this long is over. Long enough to survive a
#: film plus an argument about the ending.
IDLE = timedelta(hours=6)
#: How long a closed room's row — and so its code — stays taken.
LINGER = timedelta(days=1)

MAX_TITLE = 120
MAX_NAME = 80


@dataclass(frozen=True, slots=True)
class Occupancy:
    """How full a room is: rows on the roster, and streams actually open."""

    members: int
    watching: int


@dataclass(frozen=True, slots=True)
class RoomView:
    """A room as somebody outside this module is allowed to see it.

    A DTO rather than the row, because two things on that row are not everyone's
    business: `code`, which is the way in, and the seats' token hashes hanging
    off it.

    `code` is `None` when the caller has no business with it — a private room
    they are not in. For a public room it is not a secret at all: being listed
    *is* an invitation, and the code is how the invitation is accepted.
    """

    id: str
    code: str | None
    title: str
    is_public: bool
    is_open: bool
    host: str
    showing: Showing
    occupancy: Occupancy
    created_at: datetime


@dataclass(frozen=True, slots=True)
class Listing:
    """One page of the public rooms."""

    items: tuple[RoomView, ...]
    total: int


@dataclass(frozen=True, slots=True)
class Seated:
    """A room, and the one and only time we say a seat's token out loud."""

    room: RoomView
    token: str
    me: Watcher


@dataclass(slots=True)
class TogetherService:
    session: AsyncSession
    bus: Bus[int, RoomEvent]
    reports: Throttle[int]

    @property
    def rooms(self) -> RoomRepository:
        return RoomRepository(self.session)

    @property
    def members(self) -> MemberRepository:
        return MemberRepository(self.session)

    # --- opening and closing ------------------------------------------------

    async def open_room(
        self,
        *,
        title: str,
        public: bool,
        host: Person | None,
        display_name: str | None = None,
        media: Media | None = None,
    ) -> Seated:
        """Start a room and take the first seat in it.

        `host` is optional on purpose — see the module docstring. An anonymous
        host owns the room by holding the token this returns, and nothing else;
        losing it means losing the room, which is the honest cost of never
        having said who you are.
        """
        room = Room(
            code=await self._free_code(),
            title=_trimmed(title, MAX_TITLE) or "Watch party",
            visibility=Visibility.public if public else Visibility.private,
            host_user_id=None if host is None else host.id,
            **_media_columns(media),
        )
        seat, token = self._seat(room, host, display_name, Seat.host)
        try:
            await self.rooms.add(room)
            await self.members.add(seat)
            await self.session.commit()
        except IntegrityError as exc:
            # Two rooms racing for the same code — the check in `_free_code` is
            # a courtesy and the unique index is the referee. Translated into
            # something the caller can act on by pressing the button again.
            await self.session.rollback()
            raise Conflict("could not allocate a code") from exc

        return Seated(room=await self._view(room, code=True), token=token, me=_watcher(seat))

    async def close(self, seat: Member, *, reason: Reason = "host") -> None:
        """The host says that's the end of it.

        Everybody with a stream open is told, once, before the room stops
        existing to `GET /rooms`. A member who closes their tab instead just
        leaves; only the host can end it for everyone.
        """
        self._must_host(seat)
        await self._shut(seat.room, reason)
        await self.session.commit()

    # --- getting in and out -------------------------------------------------

    async def join(
        self,
        code: str,
        *,
        person: Person | None,
        display_name: str | None = None,
    ) -> Seated:
        """Take a seat, by code.

        The code is the whole credential, for a public room and a private one
        alike. That is not an oversight: `private` means unlisted, and anybody
        holding a code was handed it by somebody who is already inside.

        Somebody signed in who is already in this room resumes the seat they
        had — the host's, if that is what it was. Their token is reissued rather
        than remembered, because the hash is all this table keeps, and a seat
        held from two devices at once is a seat neither of them can trust.
        """
        room = await self.rooms.by_code(code)
        if room is None:
            raise NotFound("no such room")
        if not room.is_open:
            raise Invalid("that room is over")

        existing = None if person is None else await self.members.seat_of(room.id, person.id)
        if existing is not None:
            token = new_token()
            existing.token_hash = token_digest(token)
            existing.left_at = None
            existing.last_seen_at = utcnow()
            if display_name:
                existing.display_name = _trimmed(display_name, MAX_NAME) or existing.display_name
            seat = existing
        else:
            seat, token = self._seat(room, person, display_name, Seat.viewer)
            await self.members.add(seat)

        room.last_active_at = utcnow()
        await self.session.commit()
        await self._announce(room)
        return Seated(room=await self._view(room, code=True), token=token, me=_watcher(seat))

    async def leave(self, seat: Member) -> None:
        """Give the seat up.

        The host leaving ends the room. Anything else would leave a film playing
        for a group with nobody able to pause it — and handing control to the
        next person along is a decision this feature has not made yet.
        """
        if seat.is_host:
            await self._shut(seat.room, "host")
            await self.session.commit()
            return

        seat.left_at = utcnow()
        await self.session.commit()
        await self._announce(seat.room)

    # --- what is on ---------------------------------------------------------

    async def report(
        self,
        seat: Member,
        *,
        media: Media | None,
        position: float,
        paused: bool,
    ) -> Showing:
        """The host saying where the film is. Only the host may.

        Written down *and* published: the row is what a latecomer and the
        listing read, the bus is what everybody already watching hears. A write
        on every heartbeat is a row per few seconds per room, which is the same
        order as the `last_seen_at` this API already touches on every request.
        """
        self._must_host(seat)
        room = seat.room
        if not room.is_open:
            raise Invalid("that room is over")
        if not self.reports.allow(room.id):
            raise Forbidden("too many reports")

        now = utcnow()
        for column, value in _media_columns(media).items():
            setattr(room, column, value)
        room.position = max(0.0, position)
        room.paused = paused
        room.playback_at = now
        room.last_active_at = now
        seat.last_seen_at = now
        await self.session.commit()

        showing = snapshot(room)
        await self.bus.publish(room.id, showing)
        return showing

    # --- reading ------------------------------------------------------------

    async def listing(self, *, limit: int, offset: int) -> Listing:
        """The public rooms and what is playing in them."""
        rooms, total = await self.rooms.listed(limit=limit, offset=offset)
        return Listing(
            items=tuple(self._view_loaded(room, code=True) for room in rooms), total=total
        )

    async def room_for(self, public_id: str, *, seat: Member | None = None) -> RoomView:
        """One room, for somebody about to walk into it — or already in it.

        A private room is not denied to somebody who asks for it by id: they had
        to be told the id by somebody, and what they get back is a title and a
        poster with no way in attached. The code is withheld unless they are
        already seated.
        """
        room = await self.rooms.by_public_id(public_id)
        if room is None or not room.is_open:
            raise NotFound("no such room")
        inside = seat is not None and seat.room_id == room.id
        return await self._view(room, code=inside or room.is_listed)

    async def seat_for(self, token: str | None) -> Member | None:
        """Which seat this request is holding, if it is holding one."""
        if not token:
            return None
        seat = await self.members.by_digest(token_digest(token))
        if seat is None or not seat.room.is_open or not seat.present:
            return None
        return seat

    async def presence(self, room: Room) -> Presence:
        """Who is in the room, and how many are actually looking at it.

        The two numbers differ, and the gap is not a bug to be closed here. A
        browser that is shut without saying `leave` leaves its row behind, and
        nothing on this side can tell that from somebody who paused to answer
        the door. So `members` is "everybody who has not said goodbye" and
        `watching` is "streams open right now" — a client that wants the first
        to be true sends `leave` on unload, and a UI that wants a live count
        draws the second.
        """
        return Presence(
            watching=self.bus.listeners(room.id),
            members=tuple(_watcher(member) for member in await self.members.roster(room.id)),
        )

    async def touch(self, seat: Member) -> None:
        """Somebody is still there. Called when a stream opens, not per frame."""
        seat.last_seen_at = utcnow()
        seat.room.last_active_at = utcnow()
        await self.session.commit()

    # --- housekeeping -------------------------------------------------------

    async def sweep(self) -> int:
        """Close what has gone quiet and forget what closed a while ago.

        For a job; nothing calls it on a request path. Closing goes through the
        same door a host's `DELETE` does, so anybody still holding a stream on a
        room that timed out is told rather than left listening to silence.
        """
        now = utcnow()
        stale = await self.rooms.stale(before=now - IDLE)
        for room in stale:
            await self._shut(room, "idle")
        purged = await self.rooms.purge(before=now - LINGER)
        await self.session.commit()
        return len(stale) + purged

    # --- internals ----------------------------------------------------------

    def _must_host(self, seat: Member) -> None:
        if not seat.is_host:
            raise Forbidden("only the host drives")

    async def _shut(self, room: Room, reason: Reason) -> None:
        if not room.is_open:
            return
        room.closed_at = utcnow()
        await self.bus.publish(room.id, Closed(reason=reason))

    async def _announce(self, room: Room) -> None:
        await self.bus.publish(room.id, await self.presence(room))

    def _seat(
        self, room: Room, person: Person | None, display_name: str | None, seat: Seat
    ) -> tuple[Member, str]:
        token = new_token()
        return (
            Member(
                room=room,
                user_id=None if person is None else person.id,
                token_hash=token_digest(token),
                display_name=_name_for(person, display_name),
                seat=seat,
            ),
            token,
        )

    async def _free_code(self) -> str:
        """Codes are short, so collisions are possible rather than theoretical."""
        for _ in range(5):
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            if await self.rooms.by_code(code) is None:
                return code
        raise Conflict("could not allocate a code")  # pragma: no cover

    async def _view(self, room: Room, *, code: bool) -> RoomView:
        roster = await self.members.roster(room.id)
        return self._compose(room, roster, code=code)

    def _view_loaded(self, room: Room, *, code: bool) -> RoomView:
        """The same view for a room whose members came along with it.

        The listing loads twenty rooms at once; asking the database for each
        one's roster separately is the N+1 that turns a page into forty round
        trips.
        """
        return self._compose(room, [member for member in room.members if member.present], code=code)

    def _compose(self, room: Room, roster: Sequence[Member], *, code: bool) -> RoomView:
        host = next((member for member in roster if member.is_host), None)
        return RoomView(
            id=room.public_id,
            code=room.code if code else None,
            title=room.title,
            is_public=room.visibility is Visibility.public,
            is_open=room.is_open,
            host="somebody" if host is None else host.display_name,
            showing=snapshot(room),
            occupancy=Occupancy(members=len(roster), watching=self.bus.listeners(room.id)),
            created_at=room.created_at,
        )


def _trimmed(value: str | None, limit: int) -> str:
    return (value or "").strip()[:limit]


def _name_for(person: Person | None, display_name: str | None) -> str:
    """What to call this seat.

    What they typed wins, because somebody who bothered to name themselves means
    it. Then their account's name. Then nothing, which is a room full of people
    called "Guest" — so the fallback carries the four characters that tell two
    of them apart.
    """
    chosen = _trimmed(display_name, MAX_NAME)
    if chosen:
        return chosen
    if person is not None:
        return person.display_name
    return f"Guest {secrets.token_hex(2).upper()}"


#: The one place the column's vocabulary meets the wire's. Spelled out rather
#: than `.value`, so that adding a member to `models.Kind` fails here — at the
#: seam — instead of widening what the wire silently promises.
KINDS: Mapping[Kind, MediaKind] = {
    Kind.movie: "movie",
    Kind.episode: "episode",
    Kind.channel: "channel",
    Kind.other: "other",
}


def _media(room: Room) -> Media | None:
    if room.media_kind is None or room.media_id is None:
        return None
    return Media(
        kind=KINDS[room.media_kind],
        id=room.media_id,
        title=room.media_title or "",
        poster=room.media_poster,
        season=room.media_season,
        episode=room.media_episode,
    )


def snapshot(room: Room) -> Showing:
    """What the room is showing, true at the moment it is asked for.

    Every reader goes through here, so nothing anywhere hands out a position
    that was correct a minute ago — see `events.Playback.wound_to`.
    """
    playback = Playback(position=room.position, paused=room.paused, at=room.playback_at)
    return Showing(media=_media(room), playback=playback.wound_to(utcnow()))


def _media_columns(media: Media | None) -> dict[str, object]:
    """The six columns a `Media` becomes — all of them, every time.

    Written as one mapping rather than six assignments so that clearing what is
    on cannot half-happen: a room showing an episode that is handed a film must
    not keep last night's season number.
    """
    if media is None:
        return {
            "media_kind": None,
            "media_id": None,
            "media_title": None,
            "media_poster": None,
            "media_season": None,
            "media_episode": None,
        }
    return {
        "media_kind": Kind(media.kind),
        "media_id": media.id,
        "media_title": media.title,
        "media_poster": media.poster,
        "media_season": media.season,
        "media_episode": media.episode,
    }


def _watcher(member: Member) -> Watcher:
    return Watcher(id=member.public_id, name=member.display_name, is_host=member.is_host)
