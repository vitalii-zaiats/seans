"""What travels between a remote and a box, and the bus it travels on.

The fan-out itself is `core.bus` — a second module wants the same machinery and
neither may import the other. What stays here is this module's own vocabulary,
and the one thing generic fan-out has no business knowing: a box's latest state
is worth keeping, because somebody who connects a second later should not have
to wait for the next change to draw anything.
"""

from collections.abc import AsyncIterator, Mapping
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol

from api.core.bus import MemoryBus as Fanout
from api.core.schemas import JsonValue


@dataclass(frozen=True, slots=True)
class Command:
    """A remote telling a box to do something."""

    #: The remote's own correlation id, so it can tell a lost command from an
    #: ignored one.
    id: str
    method: str
    params: Mapping[str, JsonValue] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class State:
    """A box saying what it is doing.

    The payload is deliberately not interpreted here: what belongs in it is the
    app's business, and a server that had an opinion would need redeploying
    every time the player grew a field.
    """

    at: datetime
    data: Mapping[str, JsonValue] = field(default_factory=dict)


type Event = Command | State


class Bus(Protocol):
    """Where events go, and where they come from."""

    async def publish(self, device_id: int, event: Event) -> None: ...

    def latest_state(self, device_id: int) -> State | None:
        """The last thing this box said, for somebody who just connected."""
        ...

    def listen(self, device_id: int) -> AbstractAsyncContextManager[AsyncIterator[Event]]: ...

    def listeners(self, device_id: int) -> int: ...


class MemoryBus(Fanout[int, Event]):
    """Generic fan-out, plus the newest state per box."""

    def __init__(self) -> None:
        super().__init__()
        self._state: dict[int, State] = {}

    async def publish(self, device_id: int, event: Event) -> None:
        if isinstance(event, State):
            self._state[device_id] = event
        await super().publish(device_id, event)

    def latest_state(self, device_id: int) -> State | None:
        return self._state.get(device_id)

    def forget(self) -> None:
        super().forget()
        self._state.clear()
