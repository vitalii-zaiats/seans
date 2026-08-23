"""A database that lives for one test, and an app pointed at it.

SQLite rather than the Postgres the app ships on: a test suite that needs a
container running is a test suite people stop running. Nothing in this schema is
dialect-specific — no JSONB, no arrays, and the one upsert is written as a
select-then-insert precisely so it works on both.
"""

from collections.abc import AsyncIterator

import httpx2
import pytest
from api.core.database import get_session
from api.core.registry import Base
from api.main import create_app
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool


@pytest.fixture
async def sessions() -> AsyncIterator[async_sessionmaker[AsyncSession]]:
    # StaticPool keeps every connection pointed at the *same* in-memory
    # database; without it each one gets a private, empty one.
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    yield async_sessionmaker(engine, expire_on_commit=False)
    await engine.dispose()


@pytest.fixture
async def db(sessions: async_sessionmaker[AsyncSession]) -> AsyncIterator[AsyncSession]:
    async with sessions() as session:
        yield session


@pytest.fixture
async def client(
    sessions: async_sessionmaker[AsyncSession],
) -> AsyncIterator[httpx2.AsyncClient]:
    app = create_app()

    async def session_for_request() -> AsyncIterator[AsyncSession]:
        async with sessions() as session:
            yield session

    app.dependency_overrides[get_session] = session_for_request

    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url="http://test"
    ) as http:
        yield http
