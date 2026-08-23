"""Wiring for the merged catalogue.

Nothing module-level here and no cache, unlike `catalogue/`: every answer comes
out of our own database, so there is no upstream to be polite to and nobody
else deciding how stale an answer may be.
"""

from typing import Annotated

from fastapi import Depends

from api.core.deps import DB
from api.modules.titles.service import TitleService


def title_service(session: DB) -> TitleService:
    return TitleService(session)


Titles = Annotated[TitleService, Depends(title_service)]
