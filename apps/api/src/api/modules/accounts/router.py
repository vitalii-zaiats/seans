"""Auth routes, and the admin's view of who exists.

`GET /auth/me` only reads. In an API where "the user declined an account" is a
supported state, an endpoint that creates one as a side effect of being asked a
question is a trap — so becoming somebody is always an explicit POST.
"""

from typing import Annotated

from fastapi import APIRouter, Query, Request

from api.core.deps import Token
from api.errors import Unauthorized
from api.modules.accounts.deps import Accounts, Admin, CurrentUser, Viewer
from api.modules.accounts.schemas import (
    AccountOut,
    AccountPage,
    ClaimRequest,
    DeviceApproval,
    DeviceCollect,
    DeviceLinkOut,
    DeviceLinkRequest,
    DeviceLinkStatus,
    DeviceSession,
    Identity,
    LoginRequest,
    RegisterRequest,
    RenameRequest,
    RoleRequest,
)
from api.modules.accounts.service import Account

router = APIRouter(prefix="/auth", tags=["accounts"])
admin_router = APIRouter(prefix="/users", tags=["accounts"])


def _agent(request: Request) -> str | None:
    return request.headers.get("user-agent")


@router.get("/me", response_model=AccountOut)
async def me(user: Viewer) -> AccountOut:
    """Who the token belongs to. 401 when there is no token, or it is stale."""
    if user is None:
        raise Unauthorized("this needs an account")
    return AccountOut.of(Account.of(user))


@router.post("/guest", response_model=Identity, status_code=201)
async def start_guest(request: Request, accounts: Accounts) -> Identity:
    """A guest on demand, for a client that has no install to announce.

    Deliberately unconditional: calling it while already signed in starts a
    *second*, empty identity rather than handing back the first.
    """
    return Identity.of(await accounts.guest(user_agent=_agent(request)))


@router.post("/claim", response_model=Identity, status_code=201)
async def claim(
    body: ClaimRequest, request: Request, user: CurrentUser, accounts: Accounts
) -> Identity:
    """Keep the account, add the login.

    Everything watched as a guest stays where it is — this writes an email and a
    password onto that same row, and rotates the token.
    """
    return Identity.of(
        await accounts.claim(
            user,
            email=str(body.email),
            password=body.password,
            display_name=body.display_name,
            user_agent=_agent(request),
        )
    )


@router.post("/register", response_model=Identity, status_code=201)
async def register(body: RegisterRequest, request: Request, accounts: Accounts) -> Identity:
    """An account with no guest behind it.

    For somebody who ran the app locally and told us nothing until now: there is
    no history to keep, so making a guest first and claiming it would be theatre.
    """
    return Identity.of(
        await accounts.register(
            email=str(body.email),
            password=body.password,
            display_name=body.display_name,
            user_agent=_agent(request),
        )
    )


@router.post("/login", response_model=Identity)
async def login(body: LoginRequest, request: Request, accounts: Accounts) -> Identity:
    return Identity.of(
        await accounts.login(str(body.email), body.password, user_agent=_agent(request))
    )


@router.post("/logout", status_code=204)
async def logout(token: Token, accounts: Accounts) -> None:
    await accounts.logout(token)


@router.patch("/me", response_model=AccountOut)
async def rename(body: RenameRequest, user: CurrentUser, accounts: Accounts) -> AccountOut:
    return AccountOut.of(await accounts.rename(user, body.display_name))


@router.delete("/me", status_code=204)
async def forget(user: CurrentUser, accounts: Accounts) -> None:
    """The way back to local-only. Deletes the account and its sessions."""
    await accounts.forget(user)


@admin_router.get("", response_model=AccountPage)
async def list_users(
    _: Admin,
    accounts: Accounts,
    guests: Annotated[bool | None, Query(description="only guests, or only claimed")] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AccountPage:
    users, total = await accounts.all_users(limit=limit, offset=offset, guests=guests)
    return AccountPage(
        total=total,
        limit=limit,
        offset=offset,
        items=[AccountOut.of(user) for user in users],
    )


@admin_router.patch("/{public_id}/role", response_model=AccountOut)
async def set_role(public_id: str, body: RoleRequest, _: Admin, accounts: Accounts) -> AccountOut:
    return AccountOut.of(await accounts.set_role(public_id, body.role))


# --- signing in a device with no keyboard ------------------------------------
#
# Typing an email and a password with a remote is miserable, so the television
# never asks for either. It shows a code, a phone opens that code in a browser
# and approves it as whoever is signed in there, and the television collects a
# session of its own.
#
# Nothing worth stealing crosses the room. The two halves are deliberately not
# the same secret: the code is short because it is read off a screen, and
# knowing it only lets somebody *approve*; the secret stays inside the
# television and is the only thing that can collect. So even a code approved by
# the wrong person hands the token to the box that asked for it, and to nothing
# else.


@router.post("/device", response_model=DeviceLinkOut, status_code=201)
async def start_device_link(
    request: Request,
    token: Token,
    accounts: Accounts,
    body: DeviceLinkRequest | None = None,
) -> DeviceLinkOut:
    """Begin a pairing. Deliberately open: nobody is signed in yet.

    A box that already announced itself may send its token anyway — the install
    it belongs to is carried onto the session it eventually collects, so
    "sign this device out" means something later.

    The body is optional so that a build shipped before it existed still works.
    Those get the `User-Agent`, which is what this always used and which reads
    as a paragraph of browser trivia on the approval screen; anything that can
    name itself should.
    """
    named = (body.device_name or "").strip() if body else ""
    link = await accounts.start_link(
        # An empty string is not a name. Falling through to the header is the
        # same answer as sending no body at all, rather than a blank line where
        # the device should be.
        device_name=named or _agent(request),
        install_id=await accounts.install_of(token),
    )
    return DeviceLinkOut.of(link)


@router.get("/device/{code}", response_model=DeviceLinkStatus)
async def device_link_status(code: str, accounts: Accounts) -> DeviceLinkStatus:
    """What is being asked for, for the page that is about to say yes."""
    return DeviceLinkStatus.of(await accounts.link_for(code))


@router.post("/device/approve", response_model=DeviceLinkStatus)
async def approve_device_link(
    body: DeviceApproval, user: CurrentUser, accounts: Accounts
) -> DeviceLinkStatus:
    """Say yes, as somebody. The only step that needs an identity, and it is
    the phone's."""
    return DeviceLinkStatus.of(await accounts.approve_link(body.code, user))


@router.post("/device/collect", response_model=DeviceSession)
async def collect_device_link(
    body: DeviceCollect, request: Request, accounts: Accounts
) -> DeviceSession:
    """The television asking whether it may come in yet."""
    credential = await accounts.collect_link(body.secret, user_agent=_agent(request))
    if credential is None:
        return DeviceSession(status="pending")
    return DeviceSession(status="linked", identity=Identity.of(credential))
