"""Alembic environment — async engine, URL taken from the app's settings.

Keeping the URL in one place means `alembic upgrade` and the running API can
never point at different databases.
"""

import asyncio
from logging.config import fileConfig
from typing import Any

from alembic import context
from alembic.autogenerate.api import AutogenContext
from api.core.models import UTCDateTime
from api.core.registry import Base
from api.settings import settings
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def render_item(kind: str, obj: Any, autogen: AutogenContext) -> str | bool:
    """Render our own column types as the plain SQLAlchemy ones they wrap.

    A migration that imports `api.core.models` is a migration that stops working
    the day that module is renamed — and the file describes a database, not our
    code. `UTCDateTime` only normalises timezones in Python; to Postgres it has
    always been `timestamptz`, so that is what the file should say.
    """
    if kind == "type" and isinstance(obj, UTCDateTime):
        return "sa.DateTime(timezone=True)"
    return False


def configure(**extra: Any) -> None:
    context.configure(
        target_metadata=target_metadata,
        compare_type=True,
        render_item=render_item,
        **extra,
    )


def run_migrations_offline() -> None:
    configure(
        url=settings.database_url,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    configure(connection=connection)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    engine = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_async_migrations())
