"""Wiring for the remote — and the process-wide bus.

The bus is a module-level object because an in-memory one *is* process-wide:
handing each request its own would mean a command published on one and listened
for on another. The day this runs as more than one process, the composition root
builds a Redis one here instead and nothing else changes.
"""

from typing import Annotated

from fastapi import Depends

from api.core.deps import DB, Token
from api.core.throttle import Throttle
from api.errors import Forbidden, Unauthorized
from api.modules.accounts.service import AccountService
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.modules.remote.adapters import Directory
from api.modules.remote.bus import MemoryBus
from api.modules.remote.service import BURST, COMMANDS_PER_SECOND, RemoteService
from api.settings import settings

BUS = MemoryBus()
# Same reason as the bus: a limiter rebuilt per request remembers nothing.
THROTTLE: Throttle[int] = Throttle(rate=COMMANDS_PER_SECOND, burst=BURST)


def remote_service(session: DB) -> RemoteService:
    accounts = AccountService(session)
    # The whole service, because a module's service is its public face and its
    # repository is nobody else's business — even when the two methods this
    # needs would not have used the rest of it.
    installs = InstallService(session, accounts, ReleaseService(settings))
    return RemoteService(Directory(accounts, installs), BUS, THROTTLE)


Remote = Annotated[RemoteService, Depends(remote_service)]


async def calling_device(token: Token, session: DB) -> int:
    """The box making this request, from the session it is holding.

    Read rather than taken from the URL: a device that could name itself could
    name somebody else's.
    """
    if not token:
        raise Unauthorized("this needs a session")
    install_id = await AccountService(session).install_of(token)
    if install_id is None:
        raise Forbidden("this endpoint is for a device that announced itself")
    return install_id


CallingDevice = Annotated[int, Depends(calling_device)]
