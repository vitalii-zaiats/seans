"""Every query about installs.

The aggregates at the bottom are written to run unchanged on both dialects: a
conditional `SUM(CASE ...)` rather than a `FILTER` clause, `ilike` rather than a
Postgres-only operator, and no date function at all — see `statistics` for why
the day buckets are cut in Python.
"""

import uuid
from collections.abc import Iterable, Sequence
from datetime import datetime

from sqlalchemy import ColumnElement, case, func, or_, select

from api.core.repository import Repository
from api.modules.installs.models import Install, Platform


def _active(since: datetime) -> ColumnElement[int]:
    """How many rows of the group have launched since `since`.

    A conditional sum, not `COUNT(...) FILTER (WHERE ...)`: the filter clause is
    Postgres and this has to answer the same on the SQLite the tests use.
    `COALESCE` because `SUM` over an empty group is null, not zero.
    """
    return func.coalesce(func.sum(case((Install.last_seen_at >= since, 1), else_=0)), 0)


class InstallRepository(Repository[Install]):
    model = Install

    async def by_public_id(self, public_id: uuid.UUID) -> Install | None:
        found: Install | None = await self.session.scalar(
            select(Install).where(Install.public_id == public_id)
        )
        return found

    async def by_ids(self, ids: Iterable[int]) -> Sequence[Install]:
        wanted = list(ids)
        if not wanted:
            return ()
        rows = await self.session.scalars(
            select(Install).where(Install.id.in_(wanted)).order_by(Install.last_seen_at.desc())
        )
        return list(rows)

    # --- counting ------------------------------------------------------------

    async def count_created_between(self, start: datetime, end: datetime) -> int:
        """Half-open: `[start, end)`, so two adjacent windows never share a row."""
        return (
            await self.session.scalar(
                select(func.count())
                .select_from(Install)
                .where(Install.created_at >= start, Install.created_at < end)
            )
            or 0
        )

    async def count_seen_between(self, start: datetime, end: datetime) -> int:
        return (
            await self.session.scalar(
                select(func.count())
                .select_from(Install)
                .where(Install.last_seen_at >= start, Install.last_seen_at < end)
            )
            or 0
        )

    async def created_between(self, start: datetime, end: datetime) -> Sequence[datetime]:
        """Just the timestamps, for bucketing by day in Python."""
        rows = await self.session.scalars(
            select(Install.created_at).where(Install.created_at >= start, Install.created_at < end)
        )
        return list(rows)

    async def seen_between(self, start: datetime, end: datetime) -> Sequence[datetime]:
        rows = await self.session.scalars(
            select(Install.last_seen_at).where(
                Install.last_seen_at >= start, Install.last_seen_at < end
            )
        )
        return list(rows)

    # --- breakdowns ----------------------------------------------------------
    #
    # All three answer `(name, installs, active)`. The name is nullable only for
    # vendor; the other two columns are NOT NULL and the optional is there so one
    # DTO can carry all three.

    async def by_platform(self, *, active_since: datetime) -> Sequence[tuple[str, int, int]]:
        rows = await self.session.execute(
            select(Install.platform, func.count(), _active(active_since))
            .group_by(Install.platform)
            .order_by(func.count().desc(), Install.platform)
        )
        return [(platform.value, int(installs), int(active)) for platform, installs, active in rows]

    async def by_version(
        self, *, active_since: datetime, limit: int
    ) -> Sequence[tuple[str, int, int]]:
        rows = await self.session.execute(
            select(Install.version, func.count(), _active(active_since))
            .group_by(Install.version)
            .order_by(func.count().desc(), Install.version)
            .limit(limit)
        )
        return [(version, int(installs), int(active)) for version, installs, active in rows]

    async def by_vendor(
        self, *, active_since: datetime, limit: int
    ) -> Sequence[tuple[str | None, int, int]]:
        rows = await self.session.execute(
            select(Install.vendor, func.count(), _active(active_since))
            .group_by(Install.vendor)
            .order_by(func.count().desc())
            .limit(limit)
        )
        return [(vendor, int(installs), int(active)) for vendor, installs, active in rows]

    # --- listing -------------------------------------------------------------

    async def page(
        self, *, limit: int, offset: int, platform: Platform | None, query: str | None
    ) -> tuple[Sequence[Install], int]:
        """One page, newest-seen first, and the total it was cut from."""
        where = self._matching(platform, query)

        total = (
            await self.session.scalar(select(func.count()).select_from(Install).where(*where)) or 0
        )
        rows = await self.session.scalars(
            select(Install)
            .where(*where)
            .order_by(Install.last_seen_at.desc(), Install.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(rows), total

    def _matching(self, platform: Platform | None, query: str | None) -> list[ColumnElement[bool]]:
        """The filters, once, so the page and its total can never disagree."""
        where: list[ColumnElement[bool]] = []
        if platform is not None:
            where.append(Install.platform == platform)

        term = (query or "").strip()
        if not term:
            return where

        try:
            wanted = uuid.UUID(term)
        except ValueError:
            # Not a uuid, so it is meant for one of the text columns. `ilike`
            # rather than `like`: SQLAlchemy renders it as `lower() LIKE lower()`
            # on SQLite, so the search is case-insensitive on both dialects.
            like = f"%{term}%"
            where.append(or_(Install.version.ilike(like), Install.vendor.ilike(like)))
        else:
            # A uuid can only have been meant as the whole identifier. Matching
            # it as a prefix would mean casting the column to text, which is
            # spelled differently on each dialect and buys nothing.
            where.append(Install.public_id == wanted)

        return where
