"""Users and their sessions.

A guest and a member are the same table. The difference is `claimed_at`: until
it is set there is no email and no password, and the only way in is the token
the guest is holding. Claiming fills those columns in on the row that already
owns the history — no copying, no merging, no "import your guest data" screen.

Roles are orthogonal to that. A guest is a `user`; an admin is a `user` row with
`role = admin`.
"""

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import Enum, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.core.models import Base, TimestampMixin, UTCDateTime, utcnow


class Role(StrEnum):
    """Lower-case members: SQLAlchemy persists an enum by its *name*."""

    user = "user"
    admin = "admin"


def _public_id() -> str:
    return uuid.uuid4().hex


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    # What the outside world is allowed to see. Sequential ids leak how many
    # users exist and make one guessable from another; this does not.
    public_id: Mapped[str] = mapped_column(String(32), unique=True, index=True, default=_public_id)

    display_name: Mapped[str] = mapped_column(String(80))
    # Both null until the account is claimed — see the module docstring.
    email: Mapped[str | None] = mapped_column(String(320), unique=True, index=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # A varchar with a check constraint, not a Postgres enum: adding a role
    # later should not need `ALTER TYPE` in a migration.
    role: Mapped[Role] = mapped_column(
        Enum(Role, name="user_role", native_enum=False, length=20),
        default=Role.user,
        server_default=Role.user.value,
    )
    claimed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True, default=None)
    last_seen_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now()
    )

    sessions: Mapped[list["AuthSession"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )

    @property
    def is_guest(self) -> bool:
        return self.claimed_at is None

    @property
    def is_admin(self) -> bool:
        return self.role is Role.admin


class AuthSession(Base, TimestampMixin):
    """One issued token. Rows, not JWTs, so logging out actually logs out."""

    __tablename__ = "auth_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)

    # Which copy of the app collected it, when one did. Nullable because a
    # browser signing in on the landing page is not an install, and a string
    # rather than an import because this module has never met the one that owns
    # that table.
    install_id: Mapped[int | None] = mapped_column(
        ForeignKey("installs.id", ondelete="SET NULL"), nullable=True, index=True
    )

    # The SHA-256 of the token we handed over, never the token itself: reading
    # this table gets you nothing you can log in with.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)

    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    last_used_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now()
    )
    # Enough to tell "the phone" from "the television" on a sessions screen
    # later. Not proof of anything.
    user_agent: Mapped[str | None] = mapped_column(String(300), nullable=True)

    user: Mapped[User] = relationship(back_populates="sessions", lazy="joined")

    def is_live(self, now: datetime | None = None) -> bool:
        return self.expires_at > (now or utcnow())


class DeviceLink(Base, TimestampMixin):
    """A television asking a phone to sign it in.

    Typing an email and a password with a remote is miserable, so the set is
    made elsewhere: the box shows a code, a phone opens it in a browser,
    whoever is already signed in there approves it, and the box collects a
    session of its own.

    Two secrets, on purpose, and they are not the same one.

    `code` is short because it is read off a screen and carried in a QR. It is
    therefore guessable in bulk, which is why knowing it is not enough to *get*
    anything — it only lets a phone approve.

    `secret` never leaves the television. Only the holder of it can collect the
    session, so an approval a stranger tricked somebody into giving still hands
    the token to the box that asked, and to nothing else.
    """

    __tablename__ = "device_links"

    id: Mapped[int] = mapped_column(primary_key=True)

    # Short, unambiguous, and read aloud sometimes: no O/0 or I/1 in the
    # alphabet that makes it.
    code: Mapped[str] = mapped_column(String(12), unique=True, index=True)
    # Hashed like any other credential: a leaked database should not hand
    # somebody a live television session.
    secret_digest: Mapped[str] = mapped_column(String(64), unique=True, index=True)

    # What to tell the person before they approve. "Android TV", "macOS" — not
    # proof of anything, but it is the difference between approving your own
    # living room and approving somebody else's.
    device_name: Mapped[str | None] = mapped_column(String(80), nullable=True)

    # Which box asked, when it had already announced itself. Carried onto the
    # session it collects, so "sign this device out" later means something.
    install_id: Mapped[int | None] = mapped_column(
        ForeignKey("installs.id", ondelete="SET NULL"), nullable=True, index=True
    )

    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    approved_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True, default=None)
    # Handed over once. A second collection with the same secret gets nothing.
    consumed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True, default=None)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)

    # Joined, like `AuthSession.user`: this is read the moment the row is found,
    # and a lazy load there is a `MissingGreenlet` in an async request.
    user: Mapped["User | None"] = relationship(lazy="joined")

    @property
    def pending(self) -> bool:
        return self.approved_at is None

    def expired(self, now: datetime) -> bool:
        return now >= self.expires_at
