"""The two things every route needs: a session, and the token the caller sent.

Reading a bearer header is generic HTTP, not any module's business — which is
why it lives here rather than in the module that happens to mint the tokens.
"""

from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from api.core.database import get_session

DB = Annotated[AsyncSession, Depends(get_session)]


def bearer_token(request: Request) -> str | None:
    """`Authorization: Bearer <token>`, or nothing.

    No cookie fallback: every client of this API is an app that can hold a
    string, and a cookie would only add a CSRF surface nobody needs.
    """
    scheme, _, value = request.headers.get("authorization", "").partition(" ")
    return value.strip() if scheme.lower() == "bearer" and value.strip() else None


Token = Annotated[str | None, Depends(bearer_token)]
