"""The app: middleware, routers, and one place where a refusal becomes a status.

Everything else is in `modules/`. A new feature is a new folder and a line in
`modules/__init__.py` — this file should not have to grow for it.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from api import __version__
from api.core.database import engine
from api.errors import (
    ApiError,
    Conflict,
    Forbidden,
    Invalid,
    NotFound,
    Unauthorized,
    Upstream,
)
from api.modules import ROUTERS
from api.settings import settings

STATUS: dict[type[ApiError], int] = {
    NotFound: 404,
    Conflict: 409,
    Invalid: 400,
    Unauthorized: 401,
    Forbidden: 403,
    Upstream: 502,
}


class HealthOut(BaseModel):
    status: str
    version: str


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    yield
    await engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(title="super movies api", version=__version__, lifespan=lifespan)

    # No cookies anywhere in this API, so the wildcard is safe: a cross-origin
    # caller authenticates with a bearer token, which it can only have because
    # somebody gave it one.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    for router in ROUTERS:
        app.include_router(router)

    @app.exception_handler(ApiError)
    async def domain_error(request: Request, exc: ApiError) -> JSONResponse:
        """One place where a refusal becomes a status code. `api.rpc` will have
        the same table for gRPC, and neither is allowed an opinion the other
        does not share."""
        return JSONResponse({"detail": str(exc)}, status_code=STATUS.get(type(exc), 400))

    @app.get("/health", tags=["ops"])
    async def health() -> HealthOut:
        return HealthOut(status="ok", version=__version__)

    return app


app = create_app()
