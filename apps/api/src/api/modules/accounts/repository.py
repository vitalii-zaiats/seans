"""Every query about users and their sessions."""

from datetime import datetime
from typing import Any, cast

from sqlalchemy import CursorResult, delete, func, select

from api.core.repository import Repository
from api.modules.accounts.models import AuthSession, DeviceLink, Role, User


class UserRepository(Repository[User]):
    model = User

    async def get(self, row_id: int) -> User | None:
        return await self.session.get(User, row_id)

    async def by_public_id(self, public_id: str) -> User | None:
        found: User | None = await self.session.scalar(
            select(User).where(User.public_id == public_id)
        )
        return found

    async def by_email(self, email: str) -> User | None:
        """Case-folded, because nobody remembers how they typed their email."""
        found: User | None = await self.session.scalar(
            select(User).where(User.email == email.strip().lower())
        )
        return found

    async def page(
        self, *, limit: int = 50, offset: int = 0, guests: bool | None = None
    ) -> tuple[list[User], int]:
        query = select(User)
        if guests is not None:
            query = query.where(
                User.claimed_at.is_(None) if guests else User.claimed_at.is_not(None)
            )

        total = await self.session.scalar(select(func.count()).select_from(query.subquery()))
        rows = await self.session.scalars(
            query.order_by(User.created_at.desc()).limit(limit).offset(offset)
        )
        return list(rows), total or 0

    async def count_admins(self) -> int:
        return (
            await self.session.scalar(
                select(func.count()).select_from(User).where(User.role == Role.admin)
            )
            or 0
        )


class SessionRepository(Repository[AuthSession]):
    model = AuthSession

    async def by_digest(self, digest: str) -> AuthSession | None:
        found: AuthSession | None = await self.session.scalar(
            select(AuthSession).where(AuthSession.token_hash == digest)
        )
        return found

    async def revoke_all(self, user_id: int) -> None:
        await self.session.execute(delete(AuthSession).where(AuthSession.user_id == user_id))

    async def install_ids_for(self, user_id: int, *, now: datetime) -> set[int]:
        """Which installs this person currently holds a live session on.

        That is the ownership relation the remote control needs, and it needs no
        table of its own: signing a box in *is* claiming it, and signing out
        gives it up.
        """
        rows = await self.session.scalars(
            select(AuthSession.install_id).where(
                AuthSession.user_id == user_id,
                AuthSession.install_id.is_not(None),
                AuthSession.expires_at > now,
            )
        )
        return {row for row in rows if row is not None}

    async def purge_expired(self, before: datetime) -> int:
        """Housekeeping. Nothing calls this on a request path — it is for a job."""
        # `execute` is typed as returning a plain Result; a DELETE always comes
        # back as the cursor flavour, which is the one that counts rows.
        result = cast(
            "CursorResult[Any]",
            await self.session.execute(delete(AuthSession).where(AuthSession.expires_at < before)),
        )
        return result.rowcount or 0


class DeviceLinkRepository(Repository[DeviceLink]):
    model = DeviceLink

    async def by_code(self, code: str) -> DeviceLink | None:
        """Case-folded: the code is read off a screen and typed by a person."""
        found: DeviceLink | None = await self.session.scalar(
            select(DeviceLink).where(DeviceLink.code == code.strip().upper())
        )
        return found

    async def by_secret(self, digest: str) -> DeviceLink | None:
        found: DeviceLink | None = await self.session.scalar(
            select(DeviceLink).where(DeviceLink.secret_digest == digest)
        )
        return found

    async def sweep(self, now: datetime) -> int:
        """Forget the ones nobody finished.

        They are useless the moment they expire, and a table of dead codes is a
        table somebody eventually works through.
        """
        result = cast(
            "CursorResult[Any]",
            await self.session.execute(delete(DeviceLink).where(DeviceLink.expires_at < now)),
        )
        return result.rowcount or 0
