"""The declarative base and the columns every table repeats.

Each module owns its own tables; this file owns only what they have in common,
so `Base` has exactly one definition and Alembic has exactly one metadata.
"""

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, Dialect, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator


class Base(DeclarativeBase):
    pass


def utcnow() -> datetime:
    """Aware, always. A naive datetime in this schema is a bug in waiting."""
    return datetime.now(UTC)


class UTCDateTime(TypeDecorator[datetime]):
    """A timestamp that is aware going in and aware coming back.

    Postgres hands back an aware value from `timestamptz`. SQLite hands back a
    naive one, and the first thing anybody does with it is compare it to
    `utcnow()` — which raises. Normalising here means a row behaves the same
    whichever dialect read it, so the tests can run on the fast one.
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        return value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)

    def process_result_value(self, value: Any, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        moment: datetime = value
        return moment if moment.tzinfo else moment.replace(tzinfo=UTC)


class TimestampMixin:
    """`created_at` on everything, so any row can be ordered by when it appeared.

    Both defaults are there on purpose: the app writes the Python one, and a
    hand-written `INSERT` in a migration still gets the server one.
    """

    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, server_default=func.now()
    )
