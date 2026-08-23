"""The anticorruption layer, and the only file here that has met another module.

`Devices` is a question neither `accounts` nor `installs` can answer alone:
one knows who is signed in where, the other knows what a box is. This joins the
two and hands back something shaped the way `remote` asked for it, so nothing
else in this module has ever heard of either.
"""

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from api.modules.accounts.service import AccountService
from api.modules.installs.service import Device as Install
from api.modules.installs.service import InstallService


@dataclass(frozen=True, slots=True)
class Box:
    """`remote`'s own view of a box. Satisfies `ports.Device` structurally."""

    id: int
    public_id: str
    platform: str
    version: str
    last_seen_at: datetime

    @classmethod
    def of(cls, install: Install) -> "Box":
        return cls(
            id=install.id,
            public_id=str(install.public_id),
            platform=install.platform,
            version=install.version,
            last_seen_at=install.last_seen_at,
        )


@dataclass(slots=True)
class Directory:
    """Answers `remote`'s `Devices` port out of the two modules that know."""

    accounts: AccountService
    installs: InstallService

    async def owned_by(self, user_id: int) -> Sequence[Box]:
        return [
            Box.of(install)
            for install in await self.installs.devices(await self.accounts.installs_for(user_id))
        ]

    async def find(self, public_id: str, *, user_id: int) -> Box | None:
        try:
            wanted = uuid.UUID(public_id)
        except ValueError:
            # Not a uuid is not a device, and saying so is the same answer as
            # "not yours" — see the port.
            return None

        install = await self.installs.device(wanted)
        if install is None:
            return None
        if install.id not in await self.accounts.installs_for(user_id):
            return None
        return Box.of(install)
