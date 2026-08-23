"""Wiring for installs — the one file that has met all three modules.

`InstallService` asks for an `Identity` and for `Releases`; `AccountService` and
`ReleaseService` happen to be those. None of the three knows that, which is the
point: cross-module knowledge lives in a composition root, and this one is six
lines long.
"""

from typing import Annotated

from fastapi import Depends

from api.core.deps import DB
from api.modules.accounts.service import AccountService
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.settings import settings


def install_service(session: DB) -> InstallService:
    return InstallService(session, AccountService(session), ReleaseService(settings))


Installs = Annotated[InstallService, Depends(install_service)]
