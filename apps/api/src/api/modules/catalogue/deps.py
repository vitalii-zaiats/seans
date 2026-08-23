"""Wiring for the catalogue — and the caches that have to outlive a request.

Module-level for the same reason the television module's are: a cache rebuilt
per request caches nothing.

One client, and it holds one httpx connection pool. That matters here more than
it looks: a home screen asks for four rails at once, and four pools would open
four connections to the same host on every start.
"""

from typing import Annotated

from fastapi import Depends
from kinostrain import AsyncKinostrainApi, CatalogFilters, ContentCard

from api.core.cache import Cache
from api.modules.catalogue.service import CatalogueService, RailKey
from api.settings import settings

CLIENT = AsyncKinostrainApi(headers=settings.catalogue_headers)
FILTERS: Cache[str, CatalogFilters] = Cache(ttl=settings.catalogue_filters_ttl)
RAILS: Cache[RailKey, tuple[ContentCard, ...]] = Cache(ttl=settings.catalogue_rail_ttl)


def catalogue_service() -> CatalogueService:
    return CatalogueService(CLIENT, FILTERS, RAILS)


Catalogue = Annotated[CatalogueService, Depends(catalogue_service)]
