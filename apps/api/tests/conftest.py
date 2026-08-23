"""A database that lives for one test, and an app pointed at it.

Two clients over the one app, because the API answers at two roots. `client`
is based at the current version — `/api/v1` — so a test writes the path the
module's router declares and nothing has to be respelled when a version is
added. `root` is based at the server root, and the only things that live there
are `/health` and the relays.

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
from api.versions import CURRENT, prefix
from fastapi import FastAPI
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


#: Where a test that builds its own client should base it. Spelled once, so a
#: new version is not a hunt through ten fixtures.
BASE = f"http://test{prefix(CURRENT)}"


@pytest.fixture
async def app(sessions: async_sessionmaker[AsyncSession]) -> FastAPI:
    built = create_app()

    async def session_for_request() -> AsyncIterator[AsyncSession]:
        async with sessions() as session:
            yield session

    built.dependency_overrides[get_session] = session_for_request
    return built


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    """Based at the current version, so `client.get("/auth/me")` asks
    `/api/v1/auth/me` — the path the router declares, without the prefix
    repeated in three hundred places."""
    async with httpx2.AsyncClient(transport=httpx2.ASGITransport(app=app), base_url=BASE) as http:
        yield http


@pytest.fixture
async def v2(app: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    """Based at v2, for the modules only that version has — `titles/`, which is
    what v2 carries instead of `catalogue/`."""
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url=f"http://test{prefix('v2')}"
    ) as http:
        yield http


@pytest.fixture
async def root(app: FastAPI) -> AsyncIterator[httpx2.AsyncClient]:
    """The server root: `/health`, and the relays that sit outside every
    version."""
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=app), base_url="http://test"
    ) as http:
        yield http
