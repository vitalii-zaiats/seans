"""Every table in the API, in one import.

Alembic diffs `Base.metadata` against the database, and a model class nobody
imported is not in it — which autogenerate reports as "drop this table" rather
than as a mistake. So a new module means a new line here, and that is the only
thing this file is for.
"""

from api.core.models import Base
from api.modules.accounts.models import AuthSession, User
from api.modules.installs.models import Install
from api.modules.titles.models import (
    Episode,
    Season,
    Stream,
    Title,
    TitleAlias,
    TitleIdentifier,
    TitleKey,
    TitleSource,
)
from api.modules.together.models import Member, Room

__all__ = [
    "AuthSession",
    "Base",
    "Episode",
    "Install",
    "Member",
    "Room",
    "Season",
    "Stream",
    "Title",
    "TitleAlias",
    "TitleIdentifier",
    "TitleKey",
    "TitleSource",
    "User",
]
