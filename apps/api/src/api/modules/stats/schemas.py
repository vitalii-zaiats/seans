"""What the dashboard is handed.

`change` is a fraction rather than a percentage, and nullable rather than zero:
the client formats it, and "there is nothing to compare against" is a state a
percentage cannot express — see `service.Trend`.

Names on the wire are the reader's, not the table's. `installs`/`active` rather
than `count`/`seen`, because a legend has to say what it means without a
schema next to it.
"""

import uuid
from datetime import date, datetime

from pydantic import BaseModel

from api.core.schemas import Page
from api.modules.stats.ports import Day, Record, Slice
from api.modules.stats.service import Overview, Trend, Window


class WindowOut(BaseModel):
    """What every number below was measured over."""

    days: int
    active_days: int
    since: datetime
    #: Exclusive.
    until: datetime

    @classmethod
    def of(cls, window: Window) -> "WindowOut":
        return cls(
            days=window.days,
            active_days=window.active_days,
            since=window.since,
            until=window.until,
        )


class TrendOut(BaseModel):
    value: int
    previous: int
    #: `0.12` is up twelve percent. Null when the previous window was empty.
    change: float | None

    @classmethod
    def of(cls, trend: Trend) -> "TrendOut":
        return cls(value=trend.value, previous=trend.previous, change=trend.change)


class DayOut(BaseModel):
    day: date
    created: int
    #: Installs last seen on this day. Yesterday's shrinks as they come back —
    #: `installs.statistics` says why.
    seen: int

    @classmethod
    def of(cls, day: Day) -> "DayOut":
        return cls(day=day.day, created=day.created, seen=day.seen)


class SliceOut(BaseModel):
    #: Null where the dimension has no value — no installer outside android.
    name: str | None
    installs: int
    active: int

    @classmethod
    def of(cls, item: Slice) -> "SliceOut":
        return cls(name=item.name, installs=item.installs, active=item.active)


class OverviewOut(BaseModel):
    generated_at: datetime
    window: WindowOut
    #: Every install ever, ignoring the window.
    total: int
    created: TrendOut
    active: TrendOut
    #: One entry per day of the window, silent days included.
    daily: list[DayOut]
    platforms: list[SliceOut]
    versions: list[SliceOut]
    vendors: list[SliceOut]

    @classmethod
    def of(cls, overview: Overview) -> "OverviewOut":
        return cls(
            generated_at=overview.generated_at,
            window=WindowOut.of(overview.window),
            total=overview.total,
            created=TrendOut.of(overview.created),
            active=TrendOut.of(overview.active),
            daily=[DayOut.of(day) for day in overview.daily],
            platforms=[SliceOut.of(item) for item in overview.platforms],
            versions=[SliceOut.of(item) for item in overview.versions],
            vendors=[SliceOut.of(item) for item in overview.vendors],
        )


class RecordOut(BaseModel):
    """One install. `id` is the uuid the client generated, never the row's."""

    id: uuid.UUID
    platform: str
    vendor: str | None
    version: str
    registered_at: datetime
    last_seen_at: datetime

    @classmethod
    def of(cls, record: Record) -> "RecordOut":
        return cls(
            id=record.public_id,
            platform=record.platform,
            vendor=record.vendor,
            version=record.version,
            registered_at=record.registered_at,
            last_seen_at=record.last_seen_at,
        )


class RecordPage(Page):
    items: list[RecordOut]
