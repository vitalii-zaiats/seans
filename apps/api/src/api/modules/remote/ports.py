"""What this module needs from the rest of the app, stated by this module.

"Which boxes may this person drive" is a fact that lives half in `accounts`
(who is signed in where) and half in `installs` (what a box is). Neither can
answer it alone, so this states the question and `adapters.py` — the one file
allowed to have met both — answers it.
"""

from collections.abc import Sequence
from datetime import datetime
from typing import Protocol


class Device(Protocol):
    """A box, as much of one as a remote needs to name and show it."""

    @property
    def id(self) -> int: ...

    @property
    def public_id(self) -> str: ...

    @property
    def platform(self) -> str: ...

    @property
    def version(self) -> str: ...

    @property
    def last_seen_at(self) -> datetime: ...


class Devices(Protocol):
    """Who may drive what."""

    async def owned_by(self, user_id: int) -> Sequence[Device]: ...

    async def find(self, public_id: str, *, user_id: int) -> Device | None:
        """The box, or `None` — which covers both "no such box" and "not
        yours". Deliberately the same answer: telling a stranger that a device
        exists but is somebody else's is telling them something."""
        ...
