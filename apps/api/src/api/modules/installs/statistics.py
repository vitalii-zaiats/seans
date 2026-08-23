"""Installs, counted rather than fetched.

The aggregates live in this module because this module owns the table, and the
queries about a table are nobody else's to write. What reads them is the admin
dashboard, and it does so through a port of its own — see `modules/stats`, which
has never heard of this file.

Two shapes rather than one. `Statistics` answers "how is it going", and every
number in it is a count. `Records` answers "who exactly", and is a page of rows.
Keeping them apart is what lets the overview stay one round trip while the table
under it pages independently.

**Days are UTC days**, cut in Python rather than in SQL. `date_trunc` is Postgres
and `strftime` is SQLite, and the suite runs on the one the app does not ship on;
the query is bounded by the window it was asked for, so what crosses the wire is
a window's worth of timestamps rather than the table.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime


@dataclass(frozen=True, slots=True)
class Day:
    """One UTC day of the window.

    `created` is installs first written down that day — the honest "new" number.

    `seen` is installs whose *most recent* launch fell on that day, and it is a
    floor rather than a count of activity: the row keeps one `last_seen_at`, so
    an install that ran on Monday and again on Friday is counted on Friday only.
    Yesterday's `seen` therefore shrinks as those installs come back. It is the
    right shape for "who has gone quiet" and the wrong one for "daily actives",
    which would need a table this schema deliberately does not keep.
    """

    day: date
    created: int
    seen: int


@dataclass(frozen=True, slots=True)
class Slice:
    """One bar of a breakdown — a platform, a version, an installer.

    `name` is optional because `vendor` is: outside android there is no
    installer package to report, and lumping those in with android's unknowns
    would invent a fact. The reader decides how to draw a missing name.
    """

    name: str | None
    installs: int
    #: How many of them have launched since the activity cutoff.
    active: int


@dataclass(frozen=True, slots=True)
class Statistics:
    """The whole overview, from one pass over the table.

    The `previous_*` pair is the same measurement over the window immediately
    before this one, and it is here rather than computed by the caller because
    only this module knows what "the window before" cost to ask for.
    """

    total: int
    created: int
    seen: int
    previous_created: int
    previous_seen: int
    daily: tuple[Day, ...]
    platforms: tuple[Slice, ...]
    versions: tuple[Slice, ...]
    vendors: tuple[Slice, ...]


@dataclass(frozen=True, slots=True)
class Record:
    """One install, as somebody auditing the table sees it.

    Deliberately not `Device`: that one is "a box you could point a remote at"
    and answers to a different question. This one carries `vendor` and
    `registered_at`, which a remote has no business knowing.
    """

    public_id: uuid.UUID
    platform: str
    vendor: str | None
    version: str
    registered_at: datetime
    last_seen_at: datetime


@dataclass(frozen=True, slots=True)
class Records:
    """A page of them, with the total the page was cut from."""

    items: tuple[Record, ...]
    total: int
