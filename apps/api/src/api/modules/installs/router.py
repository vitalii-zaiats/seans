"""The first call an app makes.

Thin on purpose: read the request, call one service method, render the result.
Every decision in here would be a decision gRPC could not reach.
"""

from fastapi import APIRouter, Request

from api.core.deps import Token
from api.modules.installs.deps import Installs
from api.modules.installs.schemas import InitIn, InitOut

router = APIRouter(tags=["installs"])


@router.post("/init", response_model=InitOut)
async def init(body: InitIn, request: Request, token: Token, installs: Installs) -> InitOut:
    """Announce this install and collect everything it needs to start.

    Safe to call on every launch: the install row is updated rather than
    duplicated, and a session token sent along in `Authorization: Bearer` is
    kept rather than replaced.
    """
    return InitOut.of(
        await installs.initialise(
            install_id=body.id,
            platform=body.platform,
            vendor=body.vendor,
            version=body.ver,
            token=token,
            user_agent=request.headers.get("user-agent"),
        )
    )
