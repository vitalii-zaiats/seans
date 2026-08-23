"""A room people watch a film in, and the seats in it.

Two tables and one idea: **a seat is not a person.** Whoever opens a room or
joins one is handed a token that stands for their place in it, and that token —
not an account — is what says "you are the host" or "you are already in here".
It has to work that way, because a room has to admit somebody who has told us
nothing at all: no account, no guest row, no install. An account is attached to
the seat when the caller happened to have one, and it buys exactly two things —
a name worth showing, and a way back into your own seat after a reload.

The room carries what it is showing rather than a pointer to it. Nothing here
has ever heard of the catalogue, and it should not have to: the same room can
hold a film, an episode or a live channel, and the client that is already
drawing the poster is the one that knows what to call it.
"""

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import Boolean, Enum, Float, ForeignKey, Integer, String, false, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.core.models import Base, TimestampMixin, UTCDateTime, utcnow


class Visibility(StrEnum):
    """Lower-case members: SQLAlchemy persists an enum by its *name*.

    `private` means **unlisted**, and the docstring says so out loud because the
    word promises more than it delivers: a private room is missing from
    `GET /rooms` and nothing else. Its code opens it for anybody holding one,
    exactly like a link somebody forwarded.
    """

    public = "public"
    private = "private"


class Seat(StrEnum):
    """What a member may do. The host drives; everybody else follows."""

    host = "host"
    viewer = "viewer"


class Kind(StrEnum):
    """What is on. Enough to draw a listing row, and no more."""

    movie = "movie"
    episode = "episode"
    channel = "channel"
    other = "other"


def _public_id() -> str:
    return uuid.uuid4().hex


class Room(Base, TimestampMixin):
    """One watch-together room."""

    __tablename__ = "watch_rooms"

    id: Mapped[int] = mapped_column(primary_key=True)
    # What the outside world names the room by. Sequential ids leak how many
    # rooms exist and make one guessable from another; this does not.
    public_id: Mapped[str] = mapped_column(String(32), unique=True, index=True, default=_public_id)

    # Short, because it is read off a screen and sometimes read aloud — same
    # alphabet as a device link, with no O/0 or I/1 in it. Unique across every
    # room that still exists; the sweep is what frees one up again.
    code: Mapped[str] = mapped_column(String(12), unique=True, index=True)

    title: Mapped[str] = mapped_column(String(120))
    visibility: Mapped[Visibility] = mapped_column(
        # A varchar with a check constraint, not a Postgres enum: adding
        # `unlisted` later should not need `ALTER TYPE` in a migration.
        Enum(Visibility, name="room_visibility", native_enum=False, length=16),
        default=Visibility.public,
        server_default=Visibility.public.value,
    )

    # Who opened it, when they were somebody. Null for an anonymous host — the
    # room is theirs by way of the token their seat was minted with. `SET NULL`
    # rather than `CASCADE`: deleting an account should not silently take a room
    # full of other people down with it.
    host_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    # --- what is on ---------------------------------------------------------
    # All nullable together: a room that has just opened is showing nothing.
    media_kind: Mapped[Kind | None] = mapped_column(
        Enum(Kind, name="room_media_kind", native_enum=False, length=16), nullable=True
    )
    #: Whatever the client calls it — a catalogue slug, a channel id, a url it
    #: was handed. Opaque here on purpose; see the module docstring.
    media_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    media_title: Mapped[str | None] = mapped_column(String(300), nullable=True)
    media_poster: Mapped[str | None] = mapped_column(String(500), nullable=True)
    media_season: Mapped[int | None] = mapped_column(Integer, nullable=True)
    media_episode: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # --- where it has got to ------------------------------------------------
    # Kept on the row rather than only on the bus, for two reasons: the listing
    # has to answer "what is playing in there" without a stream open, and
    # somebody who joins mid-film needs a position to seek to before the host's
    # next report arrives.
    position: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")
    # `sa.false()`, not `func.false()`: the second renders as a call to a
    # function Postgres does not have.
    paused: Mapped[bool] = mapped_column(Boolean, default=True, server_default=false())
    #: When the host last said so. Position is only meaningful together with
    #: this — see `events.Playback.wound_to`.
    playback_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now()
    )

    last_active_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now(), index=True
    )
    closed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True, default=None)

    members: Mapped[list["Member"]] = relationship(
        back_populates="room", cascade="all, delete-orphan"
    )

    @property
    def is_open(self) -> bool:
        return self.closed_at is None

    @property
    def is_listed(self) -> bool:
        return self.visibility is Visibility.public and self.is_open


class Member(Base, TimestampMixin):
    """One seat in one room.

    `token_hash` is the SHA-256 of the token we handed over, never the token
    itself — the same deal as an auth session, and for the same reason: reading
    this table should get nobody into a room.
    """

    __tablename__ = "watch_members"

    id: Mapped[int] = mapped_column(primary_key=True)
    # What the roster calls this seat. Not the account's public id and not the
    # token: a client needs to pick itself out of a list of people who may all
    # have typed the same name, and that is all this is for.
    public_id: Mapped[str] = mapped_column(String(32), unique=True, index=True, default=_public_id)

    room_id: Mapped[int] = mapped_column(
        ForeignKey("watch_rooms.id", ondelete="CASCADE"), index=True
    )

    # Null for somebody who arrived with no identity at all. Not a defect —
    # anonymous is a supported way to be in a room, and the seat token is what
    # authenticates the next request either way.
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(80))
    seat: Mapped[Seat] = mapped_column(
        Enum(Seat, name="room_seat", native_enum=False, length=16),
        default=Seat.viewer,
        server_default=Seat.viewer.value,
    )

    last_seen_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now()
    )
    #: Set when they leave. The row stays, so a roster can still say who was
    #: here, and so a returning account finds its own seat instead of a second.
    left_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True, default=None)

    room: Mapped[Room] = relationship(back_populates="members", lazy="joined")

    @property
    def is_host(self) -> bool:
        return self.seat is Seat.host

    @property
    def present(self) -> bool:
        return self.left_at is None
