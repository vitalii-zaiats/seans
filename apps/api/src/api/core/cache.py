"""A small time-bounded cache with single-flight.

Infrastructure rather than anybody's domain, which is why it lives here: two
modules want one and neither may import the other.

Single-flight matters more than it looks. Without it, a cold start with fifty
boxes waking at once means fifty identical requests to somebody else's service,
which is how an address stops being welcome there.
"""

import asyncio
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field


@dataclass(slots=True)
class Cache[KeyT, ValueT]:
    """Keeps a value for `ttl` seconds, and fetches it at most once at a time."""

    ttl: float
    _entries: dict[KeyT, tuple[float, ValueT]] = field(default_factory=dict)
    _locks: dict[KeyT, asyncio.Lock] = field(default_factory=dict)

    async def through(self, key: KeyT, produce: Callable[[], Awaitable[ValueT]]) -> ValueT:
        found = self.peek(key)
        if found is not None:
            return found

        lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:
            # Somebody may have filled it while we waited for the lock, which is
            # the entire point of taking one.
            found = self.peek(key)
            if found is not None:
                return found

            value = await produce()
            self._entries[key] = (time.monotonic() + self.ttl, value)
            return value

    def peek(self, key: KeyT) -> ValueT | None:
        entry = self._entries.get(key)
        if entry is None:
            return None
        expires_at, value = entry
        if time.monotonic() >= expires_at:
            del self._entries[key]
            return None
        return value

    def forget(self) -> None:
        self._entries.clear()
        self._locks.clear()
