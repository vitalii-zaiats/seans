"""Turning "how many installs" into an answer somebody can draw.

This module holds no table. What it adds on top of the counts it is handed is
the part a chart cannot do for itself: deciding where a window starts and stops,
and comparing it to the one before.

**Windows are whole UTC days.** A window that ended "now" would put a partial day
at the right-hand end of every chart, and a partial day always looks like a
collapse. Ending at midnight after today means today's bar fills up as the day
goes on, which is the one shape a reader already knows how to discount.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta

from api.core.models import utcnow
from api.modules.stats.ports import Day, Installs, Records, Slice


@dataclass(frozen=True, slots=True)
class Window:
    """The stretch of time every number in a report was measured over."""

    days: int
    active_days: int
    #: Inclusive.
    since: datetime
    #: Exclusive — midnight after the last day, so two windows never share one.
    until: datetime
    #: An install is "active" if it has launched since this.
    active_since: datetime


@dataclass(frozen=True, slots=True)
class Trend:
    """A number, and the same number over the window before it."""

    value: int
    previous: int

    @property
    def change(self) -> float | None:
        """The move as a fraction, or `None` when there is nothing to move from.

        Zero to anything is not "+100%" and not infinite growth either — it is a
        comparison that cannot be made. Saying so lets the dashboard print a dash
        rather than a number that would be read as a rate.
        """
        if self.previous == 0:
            return None
        return (self.value - self.previous) / self.previous


@dataclass(frozen=True, slots=True)
class Overview:
    """One window of installs, ready to render."""

    #: So a client with a wrong clock can still label the chart correctly.
    generated_at: datetime
    window: Window
    #: Every install ever written down, ignoring the window.
    total: int
    created: Trend
    active: Trend
    daily: Sequence[Day]
    platforms: Sequence[Slice]
    versions: Sequence[Slice]
    vendors: Sequence[Slice]


@dataclass(slots=True)
class StatsService:
    installs: Installs

    async def overview(self, *, days: int, active_days: int, top: int) -> Overview:
        """Everything the dashboard's top half draws, in one round trip.

        One call rather than five because they are useless apart: a total with no
        window is a number nobody can act on, and a breakdown drawn over a
        different stretch of time than the chart above it is a bug that looks
        like data.
        """
        now = utcnow()
        window = self.window(days=days, active_days=active_days, now=now)
        found = await self.installs.statistics(
            since=window.since,
            until=window.until,
            active_since=window.active_since,
            top=top,
        )

        return Overview(
            generated_at=now,
            window=window,
            total=found.total,
            created=Trend(value=found.created, previous=found.previous_created),
            active=Trend(value=found.seen, previous=found.previous_seen),
            daily=found.daily,
            platforms=found.platforms,
            versions=found.versions,
            vendors=found.vendors,
        )

    async def recent(
        self, *, limit: int, offset: int, platform: str | None, query: str | None
    ) -> Records:
        """The table under the charts. Paged separately on purpose: scrolling it
        should not re-measure a month."""
        return await self.installs.records(
            limit=limit, offset=offset, platform=platform, query=query
        )

    @staticmethod
    def window(*, days: int, active_days: int, now: datetime) -> Window:
        """`days` whole UTC days, the last of which is the one in progress."""
        today = now.astimezone(UTC).date()
        until = datetime.combine(today + timedelta(days=1), time.min, tzinfo=UTC)
        return Window(
            days=days,
            active_days=active_days,
            since=until - timedelta(days=days),
            until=until,
            active_since=until - timedelta(days=active_days),
        )
