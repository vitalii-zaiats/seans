"""`GET /stream?url=…` — fetch it, and stream it back where a browser can read it.

Two shapes of answer, and the difference matters: a playlist is small, is read
whole and comes back rewritten; everything else is piped through in chunks and
never lands in memory. A segment is megabytes and there may be one every few
seconds.
"""

from collections.abc import AsyncIterator
from typing import Annotated

import httpx
from fastapi import APIRouter, Header, Query, Request
from fastapi.responses import Response, StreamingResponse

from api.errors import Upstream
from api.modules.stream.playlist import is_playlist, rewrite
from api.modules.stream.targets import target
from api.settings import settings

router = APIRouter(prefix="/stream", tags=["stream"])

#: Passed on rather than invented. `Range` is how a player seeks and how it asks
#: for a byte-range segment; without it a seek re-downloads from the start.
_FORWARD = ("range", "if-range", "accept")

#: Handed back, so a player can seek and a browser can cache exactly as it would
#: have against the origin. Deliberately no `content-encoding`: httpx has
#: already decoded the body by the time it reaches here.
_RETURN = (
    "content-type",
    "content-length",
    "content-range",
    "accept-ranges",
    "cache-control",
    "etag",
    "last-modified",
)

#: What the origin sees. HLS hosts routinely refuse a request refered from
#: anywhere but their own site, so the referer is built from the target itself
#: rather than carried from the browser — which is not allowed to set it anyway.
_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
)

#: One client for the process. A playlist is a handful of requests but a stream
#: is one every few seconds for hours, and a connection per segment is a new TLS
#: handshake per segment.
_client = httpx.AsyncClient(
    timeout=httpx.Timeout(None, connect=15.0, read=60.0),
    follow_redirects=True,
)


# GET only: Starlette adds HEAD to any route that has GET, and asking for it
# here as well is what produced two operations with one id in the schema.
@router.api_route("", methods=["GET"])
async def relay(
    request: Request,
    url: Annotated[str, Query(description="An absolute http(s) URL", max_length=2000)],
    range: Annotated[str | None, Header()] = None,
) -> Response:
    """One playlist, or one segment.

    `HEAD` answers the same headers with no body — players use it to size a file
    before deciding how to ask for it.
    """
    parts = target(url, allowed=settings.stream_hosts)

    headers = {
        "User-Agent": _USER_AGENT,
        "Referer": f"{parts.scheme}://{parts.netloc}/",
        "Origin": f"{parts.scheme}://{parts.netloc}",
        **{name: value for name, value in request.headers.items() if name.lower() in _FORWARD},
    }

    try:
        upstream = await _client.send(
            _client.build_request(request.method, url, headers=headers), stream=True
        )
    except httpx.HTTPError as exc:
        raise Upstream(f"{url} could not be fetched: {exc}") from exc

    playlist = is_playlist(upstream.headers.get("content-type"), str(upstream.url))
    if request.method != "HEAD" and playlist:
        try:
            await upstream.aread()
            body = rewrite(upstream.text, str(upstream.url))
        finally:
            await upstream.aclose()
        return Response(
            content=body,
            status_code=upstream.status_code,
            media_type=upstream.headers.get("content-type", "application/vnd.apple.mpegurl"),
            # A live playlist is rewritten every few seconds and a cached one is
            # a stream frozen in the past.
            headers={"Cache-Control": "no-store"},
        )

    returned = {name: value for name, value in upstream.headers.items() if name.lower() in _RETURN}

    if request.method == "HEAD":
        await upstream.aclose()
        return Response(status_code=upstream.status_code, headers=returned)

    async def chunks() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream.aiter_raw():
                yield chunk
        finally:
            # A viewer who seeks or closes the tab drops the connection
            # mid-segment; the upstream one has to go with it.
            await upstream.aclose()

    return StreamingResponse(chunks(), status_code=upstream.status_code, headers=returned)
