"""Wiring for the catalogue — and the caches that have to outlive a request.

Module-level for the same reason the television module's are: a cache rebuilt
per request caches nothing.

One client, and it holds one httpx connection pool. That matters here more than
it looks: a home screen asks for four rails at once, and four pools would open
four connections to the same host on every start.
"""

from typing import Annotated

import httpx
from fastapi import Depends
from kinostrain import AsyncKinostrainApi, AsyncTransport, CatalogFilters, ContentCard

from api.core.cache import Cache
from api.modules.catalogue.service import CatalogueService, RailKey
from api.settings import settings


def _transport() -> AsyncTransport | None:
    """A network stack that comes out somewhere the catalogue answers fully.

    `None` — the package's own default — unless a proxy is configured. The
    package is transport-agnostic precisely so this is a wiring decision rather
    than a change to it, and `deps.py` is where wiring belongs.

    See `settings.catalogue_proxy` for what this is working around and why it is
    only this client.
    """
    if not settings.catalogue_proxy:
        return None

    # Imported here rather than at module scope, following the package's own
    # reason: nothing in its core touches httpx, and a caller who brings a
    # different transport should never load it.
    from kinostrain.transports.httpx import AsyncHttpxTransport

    return AsyncHttpxTransport(
        httpx.AsyncClient(
            proxy=settings.catalogue_proxy,
            timeout=settings.catalogue_timeout,
            follow_redirects=True,
        )
    )


CLIENT = AsyncKinostrainApi(_transport(), headers=settings.catalogue_headers)
FILTERS: Cache[str, CatalogFilters] = Cache(ttl=settings.catalogue_filters_ttl)
RAILS: Cache[RailKey, tuple[ContentCard, ...]] = Cache(ttl=settings.catalogue_rail_ttl)


def catalogue_service() -> CatalogueService:
    return CatalogueService(CLIENT, FILTERS, RAILS)


Catalogue = Annotated[CatalogueService, Depends(catalogue_service)]
