"""One folder per feature: its tables, its queries, its rules, its routes.

Adding a feature means adding a folder and one line in `ROUTERS` — never
touching four shared files that everything else also imports.

The rule that keeps this a line rather than a web: **a module never imports
another module.** What it needs from the outside it states itself, in its own
`ports.py`, as a `Protocol` over `Literal`s — and the composition root
(`deps.py` for HTTP, `core/services.py` for everything else) is the only place
allowed to know which service satisfies which port.

    installs   asks for an Identity and for Releases; serves POST /init
    accounts   guests, claims, logins, tokens, pairing; knows nobody
    release    what to update and what to switch on; knows nobody, holds no table
    remote     driving a box from a phone; asks for Devices, holds no table
    tv         free-to-air channels from sweet.tv; knows nobody, holds no table
    catalogue  films and series from kinostrain.com; knows nobody, holds no table
    titles     the same films merged out of several catalogues — and unlike
               `catalogue`, the rows live here
    proxy      images from a host that will not let a browser have them
    stream     playlists and segments, for a browser that cannot fetch them
    playback   a player page read for the stream inside it
    stats      the admin dashboard's numbers; asks for Installs, holds no table
    together   watching one film in several places; asks for a Person, owns
               rooms and the seats in them

`remote` is the one module with an `adapters.py`, and it is there for the reason
the rule allows: "which boxes may this person drive" is half an accounts
question and half an installs one, and something has to have met both.

The two groups below are not a ranking. `ROUTERS` is the JSON API and it is
versioned; `RELAYS` are the two routes that take a URL and give back bytes, and
they answer at the server root. `api.versions` says why.
"""

from fastapi import APIRouter

from api.modules.accounts.router import admin_router as users_router
from api.modules.accounts.router import router as accounts_router
from api.modules.catalogue.router import router as catalogue_router
from api.modules.installs.router import router as installs_router
from api.modules.playback.router import router as playback_router
from api.modules.proxy.router import router as proxy_router
from api.modules.remote.router import router as remote_router
from api.modules.stats.router import router as stats_router
from api.modules.stream.router import router as stream_router
from api.modules.titles.router import router as titles_router
from api.modules.together.router import router as together_router
from api.modules.tv.router import router as tv_router

#: The API proper, as v1 has it. `api.versions` composes the rest.
ROUTERS: tuple[APIRouter, ...] = (
    installs_router,
    accounts_router,
    users_router,
    remote_router,
    tv_router,
    catalogue_router,
    stats_router,
    together_router,
    playback_router,
)

#: The merged catalogue. Not in `ROUTERS` because it is what v2 has *instead*
#: of `catalogue/` — see `api.versions`.
TITLES: APIRouter = titles_router

#: Bytes rather than JSON, at the root and outside every version: a poster
#: whose address is already in a browser's cache, and a playlist whose links
#: are already inside an `.m3u8` somebody is playing.
RELAYS: tuple[APIRouter, ...] = (
    proxy_router,
    stream_router,
)

__all__ = ["RELAYS", "ROUTERS", "TITLES"]
