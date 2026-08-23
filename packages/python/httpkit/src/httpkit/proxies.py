"""Where the proxy list comes from and whose turn it is."""

import itertools
import os
import threading
from dataclasses import dataclass, field
from pathlib import Path

ENV_VAR = "PROXY_URL"


@dataclass
class ProxyPool:
    """One or more proxy URLs, handed out round-robin.

    A rotating residential gateway is normally a single URL that gives you a
    different exit IP per connection — that's a pool of one, and the rotating is
    the provider's job. A list here rotates on our side as well.
    """

    urls: tuple[str, ...]
    # Quoted: `itertools.cycle` is subscriptable in the stubs and not at
    # runtime, and a dataclass evaluates its annotations.
    _cycle: "itertools.cycle[str]" = field(init=False, repr=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)

    def __post_init__(self) -> None:
        if not self.urls:
            raise ValueError("a proxy pool needs at least one URL")
        self._cycle = itertools.cycle(self.urls)

    def __len__(self) -> int:
        return len(self.urls)

    def next(self) -> str:
        with self._lock:  # workers share the pool
            url: str = next(self._cycle)
            return url

    @classmethod
    def from_spec(cls, spec: str | None) -> "ProxyPool | None":
        """`http://user:pass@gate:7000`, a comma-separated list, or `@file.txt`."""
        if not spec or not spec.strip():
            return None

        spec = spec.strip()
        if spec.startswith("@"):
            return cls.from_file(Path(spec[1:]))

        urls = tuple(part.strip() for part in spec.split(",") if part.strip())
        return cls(urls) if urls else None

    @classmethod
    def from_file(cls, path: Path) -> "ProxyPool | None":
        urls = tuple(
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )
        return cls(urls) if urls else None

    @classmethod
    def from_env(cls) -> "ProxyPool | None":
        return cls.from_spec(os.environ.get(ENV_VAR))


def resolve_pool(spec: str | None) -> ProxyPool | None:
    """Flag first, then `PROXY_URL`, then nothing."""
    return ProxyPool.from_spec(spec) or ProxyPool.from_env()
