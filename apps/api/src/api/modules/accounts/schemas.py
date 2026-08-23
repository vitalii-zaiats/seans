"""What the accounts module takes and hands out.

The database id never appears here — the outside world knows a user by
`public_id`, which is where `AccountOut.id` comes from.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

from api.core.models import utcnow
from api.core.schemas import Page
from api.modules.accounts.models import DeviceLink, Role
from api.modules.accounts.service import Account, Credential, DeviceRequest, DeviceStatus
from api.settings import settings


class AccountOut(BaseModel):
    id: str
    display_name: str
    email: str | None
    is_guest: bool
    is_admin: bool

    @classmethod
    def of(cls, account: Account) -> "AccountOut":
        return cls(
            id=account.id,
            display_name=account.display_name,
            email=account.email,
            is_guest=account.is_guest,
            is_admin=account.is_admin,
        )


class SessionOut(BaseModel):
    """`token` is null when the one you sent still works — keep using it."""

    token: str | None
    expires_at: datetime


class Identity(BaseModel):
    """A user together with the session that proves it.

    Returned when a session is created. Every later response carries the account
    alone — the token is the client's to keep.
    """

    session: SessionOut
    account: AccountOut

    @classmethod
    def of(cls, credential: Credential) -> "Identity":
        return cls(
            session=SessionOut(token=credential.token, expires_at=credential.expires_at),
            account=AccountOut.of(credential.account),
        )


class ClaimRequest(BaseModel):
    """Turn the guest you already are into an account you can log back into."""

    email: EmailStr
    password: str = Field(min_length=8, max_length=200)
    display_name: str | None = Field(default=None, max_length=80)


class RegisterRequest(ClaimRequest):
    """The same, for somebody who was never a guest — see `AccountService`."""


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=200)


class RenameRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)


class RoleRequest(BaseModel):
    role: Role


class AccountPage(Page):
    items: list[AccountOut]


# Where the phone should go, and how long it has to get there. Derived here
# rather than in the routes because more than one presentation layer answers
# with them, and computing it twice is how one of them ends up handing out a
# negative countdown while the other clamps at zero.


def _verify_path(code: str) -> str:
    """`/r/H7KQ2M` — the address the QR carries.

    The code is in the path rather than a query so the whole thing survives
    being read aloud, retyped, or shortened by something in between.
    """
    return f"{settings.link_base.rstrip('/')}/{code}"


def _seconds_left(until: datetime) -> int:
    """Never negative: an expired code has no time left, it has none."""
    return max(0, int((until - utcnow()).total_seconds()))


class DeviceLinkOut(BaseModel):
    """What a television is told when it asks to be signed in.

    `verify_path` rather than a URL: the server has no idea what address this
    install is reached on, and the client that draws the QR does.
    """

    code: str
    #: Never leaves the box. The only thing that can collect the session.
    secret: str
    verify_path: str
    expires_in: int

    @classmethod
    def of(cls, request: DeviceRequest) -> "DeviceLinkOut":
        return cls(
            code=request.code,
            secret=request.secret,
            verify_path=_verify_path(request.code),
            expires_in=_seconds_left(request.expires_at),
        )


class DeviceLinkStatus(BaseModel):
    """What the phone is about to approve, before it approves it."""

    code: str
    device_name: str | None
    approved: bool
    expires_in: int

    @classmethod
    def of(cls, status: DeviceStatus) -> "DeviceLinkStatus":
        return cls(
            code=status.code,
            device_name=status.device_name,
            approved=status.approved,
            expires_in=_seconds_left(status.expires_at),
        )


#: The column that has to hold it, rather than a number repeated here. A name
#: longer than this is refused outright — unlike the `User-Agent` fallback,
#: which is clamped, because a value the *client* chose is one it can be told
#: about.
DEVICE_NAME_MAX = DeviceLink.device_name.type.length or 80


class DeviceLinkRequest(BaseModel):
    """What the television calls itself.

    Optional, and the whole body is too: a build that predates this sends no
    body at all and is answered exactly as before. What it gets then is a name
    derived from its `User-Agent`, which for a browser is 117 characters of
    `Mozilla/5.0 (Macintosh; ...)` — technically a name, and useless to the
    person deciding whether this is their own living room.
    """

    #: `Android TV`, `macOS`, `Chrome`. Shown to whoever approves, and proof of
    #: nothing: anybody can claim to be anything. It is there so that a person
    #: approving two boxes can tell which is which.
    device_name: str | None = Field(default=None, max_length=DEVICE_NAME_MAX)


class DeviceApproval(BaseModel):
    code: str = Field(min_length=1, max_length=12)


class DeviceCollect(BaseModel):
    secret: str = Field(min_length=1, max_length=200)


class DeviceSession(BaseModel):
    """Not yet, or here you go.

    `pending` is the ordinary answer for as long as somebody is walking to their
    phone, so it is a status rather than an error — a television polling this
    should not have to read 404s to know it is still waiting.
    """

    status: Literal["pending", "linked"]
    identity: Identity | None = None
