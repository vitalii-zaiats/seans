"""Sending a command to a box, and hearing what it is doing.

Everything here is about *now*. A command reaches whoever is listening at the
moment it is sent and is then forgotten; nothing is written down, and a box that
was asleep wakes up with nothing to catch up on. That is the behaviour a remote
control should have — the alternative is "volume up" firing tomorrow morning.
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from api.core.models import utcnow
from api.core.schemas import JsonValue
from api.core.throttle import Throttle
from api.errors import Forbidden, NotFound
from api.modules.remote.bus import Bus, Command, State
from api.modules.remote.ports import Device, Devices

# A remote is a person pressing buttons, not a script. Anything above this is
# either a stuck key or somebody else's traffic.
COMMANDS_PER_SECOND = 10.0
BURST = 20.0


@dataclass(frozen=True, slots=True)
class Delivery:
    """What happened to a command.

    `listeners` is the honest answer to "did that work": zero means nobody was
    connected, which is a different thing from the box refusing.
    """

    id: str
    listeners: int


@dataclass(slots=True)
class RemoteService:
    devices: Devices
    bus: Bus
    throttle: Throttle[int]

    async def drivable(self, user_id: int) -> Sequence[Device]:
        """Every box this person is signed in on."""
        return await self.devices.owned_by(user_id)

    async def device_for(self, public_id: str, *, user_id: int) -> Device:
        """The box, or a refusal. Not-yours and no-such-box are the same
        answer: telling a stranger a device exists is telling them something."""
        found = await self.devices.find(public_id, user_id=user_id)
        if found is None:
            raise NotFound("no such device")
        return found

    async def send(
        self,
        device: Device,
        *,
        id: str,
        method: str,
        params: Mapping[str, JsonValue],
    ) -> Delivery:
        if not self.throttle.allow(device.id):
            raise Forbidden("too many commands")

        listeners = self.bus.listeners(device.id)
        await self.bus.publish(device.id, Command(id=id, method=method, params=params))
        return Delivery(id=id, listeners=listeners)

    async def report(self, device_id: int, data: Mapping[str, JsonValue]) -> State:
        """A box saying what it is doing. Kept, so a remote that connects a
        second later does not have to wait for the next change."""
        state = State(at=utcnow(), data=data)
        await self.bus.publish(device_id, state)
        return state

    def latest_state(self, device_id: int) -> State | None:
        return self.bus.latest_state(device_id)
