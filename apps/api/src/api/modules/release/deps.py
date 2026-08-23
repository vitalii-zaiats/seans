"""Wiring for releases. No session — nothing here touches the database."""

from typing import Annotated

from fastapi import Depends

from api.modules.release.service import ReleaseService
from api.settings import settings


def release_service() -> ReleaseService:
    return ReleaseService(settings)


Releases = Annotated[ReleaseService, Depends(release_service)]
