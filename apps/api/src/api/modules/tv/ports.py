"""What television needs from outside itself.

One thing: a way to say "this address, but through us". The relay lives in
another module and this one never learns which — `deps.py` is the only file
allowed to know that, and a `Protocol` is how the two meet without meeting.

Stated as a port rather than a string spelled out here, because unlike a
vocabulary of `Literal`s this one is a *path on our own wire*: a rename would
not show up as a mismatch, it would show up as a 404 on somebody's television.
"""

from typing import Protocol


class Relay(Protocol):
    """Somewhere a browser is allowed to fetch [url] from."""

    def __call__(self, url: str) -> str: ...
