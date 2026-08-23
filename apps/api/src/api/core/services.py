"""Every service, wired, with no request in sight.

Each module's `deps.py` does this for FastAPI: one dependency per service, all
sharing the session that request opened. None of that wiring is HTTP's business
though — a CLI, a scheduled job, a gRPC servicer or a test needs the same graph —
so here it is once more, over a session the caller owns:

    async with services() as api:
        await api.installs.initialise(install_id=..., platform=..., vendor=None, version="1.0.0")

Presentation layers sit above this and nowhere else.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from api.core.database import Session
from api.modules.accounts.service import AccountService
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.settings import settings


@dataclass(frozen=True, slots=True)
class Services:
    """One session's worth of services, already pointed at each other."""

    session: AsyncSession
    installs: InstallService
    accounts: AccountService
    release: ReleaseService


def build(session: AsyncSession) -> Services:
    """The graph, over a session somebody else opened and will close.

    The order below is the dependency order, and it is the same one `deps.py`
    arrives at by composing its dependencies — if the two ever disagree, this
    file is the one that is wrong.
    """
    accounts = AccountService(session)
    release = ReleaseService(settings)

    return Services(
        session=session,
        accounts=accounts,
        release=release,
        installs=InstallService(session, accounts, release),
    )


@asynccontextmanager
async def services() -> AsyncIterator[Services]:
    """The same graph over a session of its own — what a script wants.

    The session is closed on the way out; the engine is not, because a process
    that does two of these should not pay for two pools.
    """
    async with Session() as session:
        yield build(session)
