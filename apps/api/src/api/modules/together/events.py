"""What travels between the host and everybody watching.

Three events and nothing else. `Showing` is where the film is; `Presence` is who
else is here; `Closed` is the end of it. A member never sends anything — the
host's player is the only source of truth, so there is no command half to this
bus and no way for two people to fight over the position.

Unlike a remote-control payload, this one *is* interpreted here. It has to be:
the whole feature is arithmetic on a position, and the server is the only clock
both ends share.
"""

from dataclasses import dataclass, replace
from datetime import datetime
from typing import Literal

#: What is on. Spelled out rather than shared with the catalogue: this module
#: has never met it, and a room can just as well be holding a live channel or
#: something a client was handed a url for. Named apart from `models.Kind`
#: because the two are deliberately different things — a column's vocabulary and
#: the wire's — and `service.KINDS` is where they are made to agree.
MediaKind = Literal["movie", "episode", "channel", "other"]

#: Why a room ended.
Reason = Literal["host", "idle"]


@dataclass(frozen=True, slots=True)
class Media:
    """Enough to draw a row in the listing and a title over the player."""

    kind: MediaKind
    id: str
    title: str
    poster: str | None = None
    season: int | None = None
    episode: int | None = None


@dataclass(frozen=True, slots=True)
class Playback:
    """Where the film has got to, and when that was true."""

    position: float
    paused: bool
    at: datetime

    def wound_to(self, now: datetime) -> "Playback":
        """The same playback, moved forward to `now`.

        Somebody who opens a stream forty seconds after the host last reported
        must not seek to a forty-second-stale position, and cannot work out the
        difference themselves: their clock is their own, and the only timestamp
        they share with the host is the one this server put on it. So the
        arithmetic happens here, and what goes on the wire is already true at
        the moment it is written.

        A paused film has not moved, which is the whole point of the flag.
        """
        if self.paused:
            return self
        return replace(self, position=self.position + (now - self.at).total_seconds(), at=now)


@dataclass(frozen=True, slots=True)
class Showing:
    """What the room is playing, and where it has got to.

    `media` is `None` in a room that has just opened and nobody has put anything
    on in yet — a real state, and one the listing shows as "choosing".
    """

    media: Media | None
    playback: Playback


@dataclass(frozen=True, slots=True)
class Watcher:
    """One person in the room, as the others are allowed to see them.

    `id` names the *seat*, not whoever is in it. That is what lets a client pick
    itself out of a roster where two people typed the same name — and it is the
    reason no account id travels here: a room has no business telling everybody
    in it that the same account was also in a different one last night.
    """

    id: str
    name: str
    is_host: bool


@dataclass(frozen=True, slots=True)
class Presence:
    """Who is in the room.

    `watching` counts open streams rather than rows: somebody who joined and
    then closed their laptop is on the roster and is not watching. It is a
    per-process number, like everything else the bus knows — the day this runs
    as two processes it comes from the same Redis the bus does.
    """

    watching: int
    members: tuple[Watcher, ...]


@dataclass(frozen=True, slots=True)
class Closed:
    """The room is over. Nothing more will arrive on this stream."""

    reason: Reason


type RoomEvent = Showing | Presence | Closed
