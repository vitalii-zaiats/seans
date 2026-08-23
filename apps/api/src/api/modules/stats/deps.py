"""Wiring for the dashboard — the one file here that has met another module.

`StatsService` asks for an `Installs`; `InstallService` happens to be one.
Neither knows that, which is the point.

The whole install service, not its repository: a module's service is its public
face, and reaching past it into the queries underneath would be shorter and
wrong. That it needs an `AccountService` and a `ReleaseService` to exist is that
module's business, not this one's — a composition root paying for a constructor
it does not care about is the cost of the rule, and it is a cheap one.
"""

from typing import Annotated

from fastapi import Depends

from api.core.deps import DB
from api.modules.accounts.service import AccountService
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.modules.stats.service import StatsService
from api.settings import settings


def stats_service(session: DB) -> StatsService:
    accounts = AccountService(session)
    return StatsService(InstallService(session, accounts, ReleaseService(settings)))


Stats = Annotated[StatsService, Depends(stats_service)]
