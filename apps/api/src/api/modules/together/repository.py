"""Every query about rooms and the seats in them."""

from datetime import datetime
from typing import Any, cast

from sqlalchemy import CursorResult, delete, func, select
from sqlalchemy.orm import selectinload

from api.core.repository import Repository
from api.modules.together.models import Member, Room, Visibility


class RoomRepository(Repository[Room]):
    model = Room

    async def get(self, row_id: int) -> Room | None:
        return await self.session.get(Room, row_id)

    async def by_code(self, code: str) -> Room | None:
        """Case-folded: the code is read off a screen and typed by a person."""
        found: Room | None = await self.session.scalar(
            select(Room).where(Room.code == code.strip().upper())
        )
        return found

    async def by_public_id(self, public_id: str) -> Room | None:
        found: Room | None = await self.session.scalar(
            select(Room).where(Room.public_id == public_id)
        )
        return found

    async def listed(self, *, limit: int, offset: int) -> tuple[list[Room], int]:
        """The public rooms, busiest-first.

        Ordered by `last_active_at` rather than by how many people are in them:
        the roster is in this database and the count of open streams is not, so
        ordering by the second would mean loading every room to sort a page of
        twenty.
        """
        query = select(Room).where(Room.visibility == Visibility.public, Room.closed_at.is_(None))
        total = await self.session.scalar(select(func.count()).select_from(query.subquery()))
        rows = await self.session.scalars(
            query.options(selectinload(Room.members))
            .order_by(Room.last_active_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(rows), total or 0

    async def stale(self, *, before: datetime) -> list[Room]:
        """Rooms nobody has touched since `before`, still nominally open.

        Handed back rather than deleted, because closing one is an event people
        with a stream open have to be told about — see `TogetherService.sweep`.
        """
        rows = await self.session.scalars(
            select(Room).where(Room.closed_at.is_(None), Room.last_active_at < before)
        )
        return list(rows)

    async def purge(self, *, before: datetime) -> int:
        """Forget rooms that have been closed a while.

        Their codes come back into circulation with them, which is the only
        reason this is not just housekeeping.
        """
        result = cast(
            "CursorResult[Any]",
            await self.session.execute(
                delete(Room).where(Room.closed_at.is_not(None), Room.closed_at < before)
            ),
        )
        return result.rowcount or 0


class MemberRepository(Repository[Member]):
    model = Member

    async def by_digest(self, digest: str) -> Member | None:
        found: Member | None = await self.session.scalar(
            select(Member).where(Member.token_hash == digest)
        )
        return found

    async def seat_of(self, room_id: int, user_id: int) -> Member | None:
        """The seat this account already has in this room, if it has one.

        What makes a reload survivable for somebody signed in: they come back to
        their own seat — the host's, if that is what it was — instead of walking
        in as a second stranger with the same name.
        """
        found: Member | None = await self.session.scalar(
            select(Member).where(Member.room_id == room_id, Member.user_id == user_id)
        )
        return found

    async def roster(self, room_id: int) -> list[Member]:
        """Everybody still in the room, in arrival order.

        Which puts the host first without asking for it: the room's first seat
        is the one that opened it, and a host who reloads resumes that row
        rather than taking a new one.
        """
        rows = await self.session.scalars(
            select(Member)
            .where(Member.room_id == room_id, Member.left_at.is_(None))
            .order_by(Member.created_at, Member.id)
        )
        return list(rows)
