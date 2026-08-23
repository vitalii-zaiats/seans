"""Token buckets, for the endpoints that reach somebody else's service.

Infrastructure rather than anybody's domain, which is why it lives here: two
modules want one and neither may import the other.

Process-wide by construction. A limiter rebuilt per request has no memory and
therefore limits nothing — the first version of this lived on a service built by
a dependency and let forty presses through in a row.
"""

import time
from dataclasses import dataclass, field


@dataclass(slots=True)
class _Bucket:
    tokens: float
    rate: float
    burst: float
    at: float = field(default_factory=time.monotonic)

    def take(self) -> bool:
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.at) * self.rate)
        self.at = now
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True


class Throttle[KeyT]:
    """One bucket per key — a device, a caller's address, whatever fits."""

    def __init__(self, *, rate: float, burst: float) -> None:
        self._rate = rate
        self._burst = burst
        self._buckets: dict[KeyT, _Bucket] = {}

    def allow(self, key: KeyT) -> bool:
        bucket = self._buckets.get(key)
        if bucket is None:
            bucket = _Bucket(tokens=self._burst, rate=self._rate, burst=self._burst)
            self._buckets[key] = bucket
        return bucket.take()

    def forget(self) -> None:
        """For tests, and for keys nobody has used in a long time."""
        self._buckets.clear()
