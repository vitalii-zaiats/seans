"""What this module needs from the rest of the app, stated by this module.

The port lives with the *consumer*, and that is the whole trick. `InstallService`
says "I need somewhere to get a session" and "I need somebody who knows about
releases"; two other services happen to satisfy those. Nothing here imports
them, neither of them has heard of installs, and `deps.py` is the only file that
has met all three.

Two details make it work without a single cross-module import:

* the returned shapes are `Protocol`s, so a frozen dataclass over in the
  provider satisfies one by having the right attributes — no shared base, no
  import;
* the vocabularies are `Literal`s rather than a shared enum, so both sides spell
  out the same strings independently. That duplication is the anticorruption
  layer doing its job: if `release` ever renames a channel, this module keeps
  compiling and the mismatch surfaces here, at the seam, instead of leaking a
  foreign enum through to the wire.
"""

from collections.abc import Mapping
from datetime import datetime
from typing import Literal, Protocol

#: What the client should do about the version it is running.
UpdateAction = Literal["none", "optional", "required"]
#: Where a new version would come from.
UpdateChannel = Literal["store", "self", "auto"]


class Account(Protocol):
    """Whoever the session belongs to, as much of them as init needs to say."""

    @property
    def id(self) -> str: ...

    @property
    def display_name(self) -> str: ...

    @property
    def email(self) -> str | None: ...

    @property
    def is_guest(self) -> bool: ...

    @property
    def is_admin(self) -> bool: ...


class Session(Protocol):
    """A live session, minted by somebody else."""

    @property
    def token(self) -> str | None:
        """`None` when the caller already had one that still works."""
        ...

    @property
    def expires_at(self) -> datetime: ...

    @property
    def account(self) -> Account: ...


class Identity(Protocol):
    """Somewhere to get a session for an install."""

    async def establish(
        self,
        install_id: int,
        token: str | None = None,
        *,
        user_agent: str | None = None,
    ) -> Session: ...


class UpdatePlan(Protocol):
    """What to tell the client about the version it reported."""

    @property
    def action(self) -> UpdateAction: ...

    @property
    def channel(self) -> UpdateChannel: ...

    @property
    def current(self) -> str: ...

    @property
    def latest(self) -> str: ...

    @property
    def minimum(self) -> str: ...

    @property
    def url(self) -> str | None: ...


class Releases(Protocol):
    """Somebody who knows which version ships where, and what it may do."""

    def plan(self, *, platform: str, vendor: str | None, version: str) -> UpdatePlan: ...

    def features(self, *, vendor: str | None) -> Mapping[str, bool]: ...
