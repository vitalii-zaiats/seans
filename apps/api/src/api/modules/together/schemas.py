"""What the watch-together endpoints take and hand back.

The database id never appears here — a room is known by `public_id`, a seat by
its own, and the only secret that ever crosses this boundary is a seat's token,
said once, at the moment the seat is minted.
"""

from datetime import datetime

from pydantic import BaseModel, Field

from api.core.schemas import Page
from api.modules.together.events import Media, MediaKind, Playback, Presence, Showing, Watcher
from api.modules.together.service import MAX_NAME, MAX_TITLE, RoomView, Seated


class MediaModel(BaseModel):
    """What is on. The same shape going in and coming out.

    The server does not look any of this up: the client that is already drawing
    the poster is the one that knows what to call it, and a room can hold a film,
    an episode or a live channel with equal indifference. `id` is whatever that
    client calls it — a catalogue slug, a channel id — and is handed back to
    everybody else so their player can open the same thing.
    """

    kind: MediaKind
    id: str = Field(min_length=1, max_length=200)
    title: str = Field(min_length=1, max_length=300)
    poster: str | None = Field(default=None, max_length=500)
    season: int | None = Field(default=None, ge=0)
    episode: int | None = Field(default=None, ge=0)

    @classmethod
    def of(cls, media: Media) -> "MediaModel":
        return cls(
            kind=media.kind,
            id=media.id,
            title=media.title,
            poster=media.poster,
            season=media.season,
            episode=media.episode,
        )

    def media(self) -> Media:
        return Media(
            kind=self.kind,
            id=self.id,
            title=self.title,
            poster=self.poster,
            season=self.season,
            episode=self.episode,
        )


class PlaybackOut(BaseModel):
    """Where the film is, and when that was true.

    `at` is the server's clock, and `position` is already wound forward to it —
    a client seeks to `position` and does not have to work out how long the
    answer spent in flight. See `events.Playback.wound_to`.
    """

    position: float
    paused: bool
    at: datetime

    @classmethod
    def of(cls, playback: Playback) -> "PlaybackOut":
        return cls(position=playback.position, paused=playback.paused, at=playback.at)


class ShowingOut(BaseModel):
    """`media` is null in a room where nobody has put anything on yet."""

    media: MediaModel | None
    playback: PlaybackOut

    @classmethod
    def of(cls, showing: Showing) -> "ShowingOut":
        return cls(
            media=None if showing.media is None else MediaModel.of(showing.media),
            playback=PlaybackOut.of(showing.playback),
        )


class WatcherOut(BaseModel):
    """One person in the room. `id` names the seat, never the account."""

    id: str
    name: str
    is_host: bool

    @classmethod
    def of(cls, watcher: Watcher) -> "WatcherOut":
        return cls(id=watcher.id, name=watcher.name, is_host=watcher.is_host)


class PresenceOut(BaseModel):
    """Who is here. `watching` counts open streams; `members` is the roster —
    somebody who joined and shut their laptop is on one and not the other."""

    watching: int
    members: list[WatcherOut]

    @classmethod
    def of(cls, presence: Presence) -> "PresenceOut":
        return cls(
            watching=presence.watching,
            members=[WatcherOut.of(member) for member in presence.members],
        )


class ClosedOut(BaseModel):
    """The last thing a stream ever says."""

    reason: str


class RoomOut(BaseModel):
    """A room, as the listing and the room page draw it.

    `code` is null when the caller has no business with it — a private room they
    are not in. For a public room it is not withheld: being listed *is* an
    invitation, and the code is how one is accepted.
    """

    id: str
    code: str | None
    title: str
    is_public: bool
    is_open: bool
    #: The host's display name. Everybody in a room can see who is driving.
    host: str
    showing: ShowingOut
    members: int
    watching: int
    created_at: datetime

    @classmethod
    def of(cls, room: RoomView) -> "RoomOut":
        return cls(
            id=room.id,
            code=room.code,
            title=room.title,
            is_public=room.is_public,
            is_open=room.is_open,
            host=room.host,
            showing=ShowingOut.of(room.showing),
            members=room.occupancy.members,
            watching=room.occupancy.watching,
            created_at=room.created_at,
        )


class RoomPage(Page):
    items: list[RoomOut]


class SeatOut(BaseModel):
    """A room and the seat you have just taken in it.

    `token` is the only credential this feature has, and this is the one and
    only time it is said out loud. It stands for the seat, not for you: an
    anonymous host who loses it loses the room, which is the honest cost of
    never having said who you are.
    """

    room: RoomOut
    token: str
    me: WatcherOut

    @classmethod
    def of(cls, seated: Seated) -> "SeatOut":
        return cls(
            room=RoomOut.of(seated.room),
            token=seated.token,
            me=WatcherOut.of(seated.me),
        )


class OpenRequest(BaseModel):
    """Start a room.

    Nothing here is required to be signed in for, and `display_name` is how
    somebody who is not says what to call them.
    """

    title: str = Field(default="", max_length=MAX_TITLE)
    #: Public rooms are listed by `GET /rooms`. Private ones are not, and that
    #: is the whole difference — see `models.Visibility`.
    is_public: bool = True
    display_name: str | None = Field(default=None, max_length=MAX_NAME)
    #: What to put on straight away, for a room opened from a film's page.
    media: MediaModel | None = None


class JoinRequest(BaseModel):
    code: str = Field(min_length=1, max_length=12)
    display_name: str | None = Field(default=None, max_length=MAX_NAME)


class ReportRequest(BaseModel):
    """The host saying where the film has got to.

    **The whole picture, not a patch.** A report with no `media` means nothing
    is on, not "same as before" — so a heartbeat carries what it is playing
    every time. That is a few hundred bytes every few seconds, and it is what
    makes this endpoint idempotent: whatever arrives last is what the room is,
    with no way for a dropped message to leave a stale title over a new film.
    """

    media: MediaModel | None = None
    position: float = Field(default=0.0, ge=0)
    paused: bool = False
