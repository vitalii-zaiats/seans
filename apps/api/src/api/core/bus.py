"""Fan-out: one publisher, however many listeners, per key.

Infrastructure rather than anybody's domain, which is why it lives here: two
modules want one — commands going to a box, a film's position going to everybody
watching it — and neither may import the other. What a key *means* is the
module's business; this only knows that events published under one come out of
every stream listening on it.

`MemoryBus` is enough for a single API process, which is what this runs as
today. Two processes behind a balancer need a real one — a `POST` landing on
instance A while the listener is held by instance B still has to arrive — and
that is a Redis implementation of the same protocol, not a change anywhere else.
"""

import asyncio
from collections.abc import AsyncIterator
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Protocol

# A listener that cannot keep up is a listener on a bad connection. Holding
# everything for it would grow without bound, so the oldest goes.
QUEUE_LIMIT = 32


class Bus[KeyT, EventT](Protocol):
    """Where events go, and where they come from."""

    async def publish(self, key: KeyT, event: EventT) -> None: ...

    def listen(self, key: KeyT) -> AbstractAsyncContextManager[AsyncIterator[EventT]]: ...

    def listeners(self, key: KeyT) -> int: ...


class MemoryBus[KeyT, EventT]:
    """Everything in one process."""

    def __init__(self) -> None:
        self._listeners: dict[KeyT, set[asyncio.Queue[EventT]]] = {}

    async def publish(self, key: KeyT, event: EventT) -> None:
        for queue in tuple(self._listeners.get(key, ())):
            if queue.full():
                # Drop the oldest rather than the newest: for both users of this
                # bus, the most recent event is the one worth having — a stale
                # button press and a stale position are equally useless.
                queue.get_nowait()
            queue.put_nowait(event)

    @asynccontextmanager
    async def listen(self, key: KeyT) -> AsyncIterator[AsyncIterator[EventT]]:
        queue: asyncio.Queue[EventT] = asyncio.Queue(maxsize=QUEUE_LIMIT)
        self._listeners.setdefault(key, set()).add(queue)
        try:
            yield self._drain(queue)
        finally:
            listeners = self._listeners.get(key)
            if listeners is not None:
                listeners.discard(queue)
                if not listeners:
                    del self._listeners[key]

    def listeners(self, key: KeyT) -> int:
        """How many streams are open on this key. Callers report it, so a
        publisher can tell "nothing happened" from "nobody was listening"."""
        return len(self._listeners.get(key, ()))

    async def _drain(self, queue: asyncio.Queue[EventT]) -> AsyncIterator[EventT]:
        while True:
            yield await queue.get()

    def forget(self) -> None:
        """For tests. A process-wide object must not carry one test's listeners
        into the next."""
        self._listeners.clear()
