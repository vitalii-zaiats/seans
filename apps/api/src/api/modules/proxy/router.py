"""Passing an image through, and nothing more.

Deliberately not a general proxy. The path mirrors one configured upstream and
nothing else can be asked for, so there is no version of this that turns into an
open relay for somebody else's traffic — which is what a `?url=` parameter would
have been the moment it shipped.

No caching yet. When it comes it belongs here, keyed by the path, and nothing
above has to change: the address a client already holds stays the same.
"""

from collections.abc import AsyncIterator

import httpx
from fastapi import APIRouter, Header, Request
from fastapi.responses import StreamingResponse

from api.errors import Upstream
from api.settings import settings

router = APIRouter(prefix="/proxy", tags=["proxy"])

#: Passed on rather than invented. `Range` because a player asks for one and a
#: browser asks for one on a reload.
_FORWARD = ("range", "if-none-match", "if-modified-since", "accept")

#: Handed back, so a browser can cache and revalidate exactly as it would have
#: against the origin.
_RETURN = (
    "content-type",
    "content-length",
    "content-range",
    "accept-ranges",
    "etag",
    "last-modified",
    "cache-control",
)

#: One client for the process, so this does not open a connection per poster on
#: a home screen that asks for thirty at once.
_client = httpx.AsyncClient(timeout=settings.proxy_timeout, follow_redirects=True)


@router.get("/{path:path}")
async def image(
    path: str,
    request: Request,
    accept: str | None = Header(default=None),
) -> StreamingResponse:
    """One file from the upstream this proxy mirrors.

    Streamed rather than read into memory: a poster is small, but nothing here
    knows that, and buffering somebody else's file before answering is how a
    proxy becomes the slowest thing in the chain.
    """
    url = f"{settings.proxy_upstream.rstrip('/')}/{path}"
    headers = {name: value for name, value in request.headers.items() if name.lower() in _FORWARD}

    try:
        upstream = await _client.send(
            _client.build_request("GET", url, headers=headers), stream=True
        )
    except httpx.HTTPError as exc:
        raise Upstream(f"{url} could not be fetched: {exc}") from exc

    if upstream.status_code >= 400:
        await upstream.aclose()
        raise Upstream(f"{url} answered {upstream.status_code}")

    async def body() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream.aiter_raw():
                yield chunk
        finally:
            await upstream.aclose()

    return StreamingResponse(
        body(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
        headers={
            **{name: value for name, value in upstream.headers.items() if name.lower() in _RETURN},
            # The whole reason this endpoint exists.
            "Access-Control-Allow-Origin": "*",
        },
    )
