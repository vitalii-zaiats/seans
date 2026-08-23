"""Which routers answer under which version prefix.

The JSON API is versioned and moves as one: everything in it lives under
`/api/v1`. A version is a *tuple of routers* rather than a folder of copies,
because the next one will differ from this one in a module or two and agree
with it in nine — spelling it this way means the nine are the same objects,
not nine copies somebody has to keep identical by hand.

**The relays are not versioned, and that is the point.** `/proxy/…` and
`/stream` take a URL and hand back bytes: there is no schema to change. Their
addresses are also not in anybody's source — they are written into an `.m3u8`
a player is halfway through, into an `<img src>` a browser was told to cache
for a week, into a poster path a box wrote down last night. Moving those on a
version bump would break every one of them and buy nothing, so they stay at
the root and the version prefix is not their business. `/health` is at the
root for the same reason: it answers to a load balancer, not to a client.
"""

from collections.abc import Mapping

from fastapi import APIRouter

from api.modules import ROUTERS, TITLES
from api.modules.catalogue.router import router as catalogue_router

#: What every versioned path starts with.
ROOT = "/api"

#: v2 is v1 with one module swapped. `catalogue/` asks kinostrain and passes
#: the answer on; `titles/` answers out of our own tables, from two catalogues
#: merged into one. Everything else — accounts, pairing, the remote, television
#: — is the same object under both prefixes rather than a copy of it.
V2: tuple[APIRouter, ...] = (
    *(router for router in ROUTERS if router is not catalogue_router),
    TITLES,
)

#: Every version this build answers on, oldest first. A version stays here for
#: as long as something is still speaking it, and leaves in one line.
VERSIONS: Mapping[str, tuple[APIRouter, ...]] = {"v1": ROUTERS, "v2": V2}

#: What a client written today should speak. Named so that a client, a test or
#: a document that has no reason to pin one can say "the current one" and mean
#: it — rather than spelling `v1` in fifty places and finding them all later.
CURRENT = "v1"


def prefix(version: str) -> str:
    """`/api/v1`. A function so that a prefix cannot be spelled two ways."""
    return f"{ROOT}/{version}"
