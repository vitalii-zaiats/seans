"""Rows in, rows out. Private to this module — the service is the public face.

Two things live here that are worth naming.

**The keypad query is a range, not a `LIKE`.** `code >= '489' AND code < '48:'`
selects exactly the codes beginning `489`, and it does so through a plain btree
index on either dialect. `LIKE '489%'` would need `text_pattern_ops` on
Postgres and fall back to a sequential scan without it, and the tests run on
SQLite where none of that applies — a query that behaves differently on the two
is a query that is only tested on one.

**A load replaces rather than updates.** The importer builds the whole
catalogue in memory, and merging it row by row into an existing one would mean
deciding what to do about a title whose sources have since been regrouped.
Deleting and re-inserting inside one transaction is honest and takes seconds.
"""

from collections.abc import Sequence

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from api.modules.titles.models import (
    Episode,
    Season,
    Stream,
    Title,
    TitleAlias,
    TitleIdentifier,
    TitleKey,
    TitleSource,
)

#: The character after `9`, so that `'48' + AFTER_NINE` sorts above every code
#: that starts with `48` and below anything that does not.
AFTER_NINE = ":"


def upper_bound(keys: str) -> str:
    """The exclusive end of the range a prefix covers."""
    return keys[:-1] + chr(ord(keys[-1]) + 1)


class TitleRepository:
    """Every query this module makes."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def by_keys(self, keys: str, *, limit: int) -> Sequence[Title]:
        """Titles whose keypad code starts with `keys`, best first.

        Ordered by rank and then by how much of the code the query covers: a
        title spelled out completely beats one that merely begins the same way,
        which on a keypad is the difference between finding a late word and
        never finding it.
        """
        codes = (
            select(TitleKey.title_id, func.min(func.length(TitleKey.code)).label("shortest"))
            .where(TitleKey.code >= keys, TitleKey.code < upper_bound(keys))
            .group_by(TitleKey.title_id)
            .subquery()
        )
        found = (
            select(Title)
            .join(codes, codes.c.title_id == Title.id)
            .order_by((codes.c.shortest == len(keys)).desc(), Title.rank.desc(), codes.c.shortest)
            .limit(limit)
        )
        return (await self._session.scalars(found)).all()

    async def by_slug(self, slug: str) -> Title | None:
        found = (
            select(Title)
            .where(Title.slug == slug)
            .options(
                selectinload(Title.sources),
                selectinload(Title.identifiers),
            )
        )
        title: Title | None = await self._session.scalar(found)
        return title

    async def streams_for(self, title_id: int) -> Sequence[Stream]:
        found = select(Stream).where(Stream.title_id == title_id).order_by(Stream.id)
        return (await self._session.scalars(found)).all()

    async def seasons_for(self, title_id: int) -> Sequence[Season]:
        found = select(Season).where(Season.title_id == title_id).order_by(Season.number)
        return (await self._session.scalars(found)).all()

    async def episodes_for(self, season_ids: Sequence[int]) -> Sequence[Episode]:
        if not season_ids:
            return []
        found = (
            select(Episode)
            .where(Episode.season_id.in_(season_ids))
            .order_by(Episode.season_id, Episode.number)
        )
        return (await self._session.scalars(found)).all()

    async def count(self) -> int:
        return await self._session.scalar(select(func.count()).select_from(Title)) or 0

    async def clear(self) -> None:
        """Everything, in one statement per table.

        The children go first even though every foreign key cascades: SQLite
        only enforces `ON DELETE CASCADE` when `PRAGMA foreign_keys` is on, and
        a load that half-worked on one dialect and fully on the other is worse
        than one that is explicit.
        """
        for table in (Stream, Episode, Season, TitleKey, TitleAlias, TitleIdentifier, TitleSource):
            await self._session.execute(delete(table))
        await self._session.execute(delete(Title))
