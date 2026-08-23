"""Engine and session plumbing."""

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from api.settings import settings

engine = create_async_engine(settings.database_url, pool_pre_ping=True)

# `expire_on_commit=False` because services commit and then read the row to
# build a DTO. Expiring would turn that read into a lazy load on a closed
# greenlet — the classic async SQLAlchemy trap.
Session = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with Session() as session:
        yield session
