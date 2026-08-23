"""The three ways a route can ask who is calling.

    Viewer       whoever they are, or nobody. Never creates anything.
    CurrentUser  somebody, guaranteed, or a refusal.
    Admin        somebody with the role, or a refusal.

Note what is *not* here: a dependency that mints a guest. In this API the guest
is created by `POST /init`, deliberately and once, or by `POST /auth/guest` when
somebody asks. A GET that quietly creates an account would make "the user
declined an account" impossible to honour.
"""

from typing import Annotated

from fastapi import Depends

from api.core.deps import DB, Token
from api.errors import Forbidden, Unauthorized
from api.modules.accounts.models import User
from api.modules.accounts.service import AccountService


def account_service(session: DB) -> AccountService:
    return AccountService(session)


Accounts = Annotated[AccountService, Depends(account_service)]


async def viewer(token: Token, accounts: Accounts) -> User | None:
    """Personalise if we can, stay anonymous if we cannot."""
    return await accounts.identify(token)


Viewer = Annotated[User | None, Depends(viewer)]


async def current_user(user: Viewer) -> User:
    if user is None:
        raise Unauthorized("this needs an account")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


async def admin(user: CurrentUser) -> User:
    if not user.is_admin:
        raise Forbidden("admins only")
    return user


Admin = Annotated[User, Depends(admin)]
