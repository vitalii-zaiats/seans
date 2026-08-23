"""What the dashboard needs, stated by the dashboard.

The port lives with the consumer, so this module says "I need somebody who can
count installs" and something else happens to be that somebody. Nothing here
imports `installs`, `installs` has never heard of this folder, and `deps.py` is
the only file that has met both.

The shapes are `Protocol`s, so the frozen dataclasses over in the provider
satisfy them by having the right attributes — no shared base class and no
import. `Platform` is a `Literal` spelled out again rather than a shared enum:
if that module ever adds `ios`, this one keeps working and the mismatch surfaces
here, at the seam, instead of quietly widening what the dashboard may filter by.
"""

import uuid
from collections.abc import Sequence
from datetime import date, datetime
from typing import Literal, Protocol

#: Where a copy of the app runs. The same four strings the other side spells out.
Platform = Literal["android", "linux", "windows", "web"]


class Day(Protocol):
    """One day of the window."""

    @property
    def day(self) -> date: ...

    @property
    def created(self) -> int: ...

    @property
    def seen(self) -> int:
        """Installs whose most recent launch fell on this day — a floor, not a
        count of activity. The provider's docstring explains what it costs."""
        ...


class Slice(Protocol):
    """One bar of a breakdown."""

    @property
    def name(self) -> str | None:
        """Null where the dimension genuinely has no value — an installer
        package outside android, for instance."""
        ...

    @property
    def installs(self) -> int: ...

    @property
    def active(self) -> int: ...


class Statistics(Protocol):
    """Everything the overview draws, from one call."""

    @property
    def total(self) -> int: ...

    @property
    def created(self) -> int: ...

    @property
    def seen(self) -> int: ...

    @property
    def previous_created(self) -> int:
        """The same measurement over the window before this one."""
        ...

    @property
    def previous_seen(self) -> int: ...

    @property
    def daily(self) -> Sequence[Day]: ...

    @property
    def platforms(self) -> Sequence[Slice]: ...

    @property
    def versions(self) -> Sequence[Slice]: ...

    @property
    def vendors(self) -> Sequence[Slice]: ...


class Record(Protocol):
    """One install, listed."""

    @property
    def public_id(self) -> uuid.UUID: ...

    @property
    def platform(self) -> str: ...

    @property
    def vendor(self) -> str | None: ...

    @property
    def version(self) -> str: ...

    @property
    def registered_at(self) -> datetime: ...

    @property
    def last_seen_at(self) -> datetime: ...


class Records(Protocol):
    @property
    def items(self) -> Sequence[Record]: ...

    @property
    def total(self) -> int: ...


class Installs(Protocol):
    """Somebody who can count installs and list them."""

    async def statistics(
        self, *, since: datetime, until: datetime, active_since: datetime, top: int
    ) -> Statistics: ...

    async def records(
        self, *, limit: int, offset: int, platform: str | None = None, query: str | None = None
    ) -> Records: ...
