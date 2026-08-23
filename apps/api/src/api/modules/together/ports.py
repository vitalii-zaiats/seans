"""What this module needs from the rest of the app, stated by this module.

Almost nothing, and that is the point. A room needs a name to put next to a
seat, and — for somebody who is signed in — a stable id so that reloading the
page finds their own seat instead of opening a second one. That is the whole
list. Nothing here imports `accounts`; the router hands over whoever the request
turned out to belong to, and a `User` row satisfies this by having the three
attributes. If that module ever renames one, the mismatch surfaces at this seam
instead of leaking through to the wire.

There is deliberately no port for the catalogue. A room carries the title and
the poster the client was already drawing — see `models`.
"""

from typing import Protocol


class Person(Protocol):
    """Whoever the caller turned out to be, when they turned out to be anybody.

    A guest and a claimed account are the same shape here on purpose: inside a
    room the difference buys nothing, and a roster that showed it would be
    telling everybody in the room something about somebody that the room is not
    about.
    """

    @property
    def id(self) -> int:
        """The row id, for the seat's foreign key. Never leaves this module."""
        ...

    @property
    def public_id(self) -> str: ...

    @property
    def display_name(self) -> str: ...
