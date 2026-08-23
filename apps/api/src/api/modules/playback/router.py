"""`POST /playback/resolve` — an embed page in, a playable address out.

The one call a browser cannot make for itself, and for two reasons rather than
one: the player page is served from a host that sends no CORS header, and it
serves a different page — or none — to a request that does not look like the
site's own iframe. A page cannot set `Referer`. This can.

Takes the embed URL the catalogue already handed out rather than a slug, which
is what keeps this module from having to know anything about the catalogue: the
caller has the links in `player_data` already, and passing one back is cheaper
than looking it up twice.
"""

from typing import Annotated

import httpx
from fastapi import APIRouter, Body
from pydantic import BaseModel, Field

from api.errors import Invalid, NotFound, Upstream
from api.modules.playback.extract import Stream, episodes, streams
from api.settings import settings

router = APIRouter(prefix="/playback", tags=["playback"])

#: What the player page is asked with. It answers 400 to a request carrying
#: neither.
_HEADERS = {
    "Referer": settings.playback_referer,
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 12; BRAVIA) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    ),
}

_client = httpx.AsyncClient(timeout=settings.playback_timeout, follow_redirects=True)


class ResolveIn(BaseModel):
    #: One of the `link`s from a season's `player_data` or `episode_players`.
    url: str = Field(max_length=2000)
    #: For a serial page that carries a playlist. Without them the first leaf
    #: wins, which is right for a film and wrong for episode nine.
    season: int | None = Field(default=None, ge=1)
    episode: int | None = Field(default=None, ge=1)


class StreamOut(BaseModel):
    url: str
    #: The player's own words: a quality tag, a dub, or the whole playlist path.
    label: str | None
    #: `playerjs` when read from the configuration, `page-scan` when the page
    #: was swept instead — a guess, and worth knowing as one.
    source: str


class ResolveOut(BaseModel):
    """Every stream on the page, best guess first.

    A list rather than one address: a page carries several qualities and
    sometimes several dubs, and which of those a client wants is the client's
    business. The first is the one to play when nobody has an opinion.
    """

    streams: list[StreamOut]


@router.post("/resolve", response_model=ResolveOut)
async def resolve(body: Annotated[ResolveIn, Body()]) -> ResolveOut:
    """Open the player page and read what is playable off it.

    404 when the page loads and holds nothing — which is an ordinary state for a
    title the catalogue lists but nobody has uploaded yet, and a different thing
    from the page being unreachable.
    """
    host = httpx.URL(body.url).host
    if not host or not any(
        host == allowed.lstrip(".") or host.endswith(allowed) for allowed in settings.playback_hosts
    ):
        raise Invalid(f"not a player this API reads: {host or body.url}")

    try:
        page = await _client.get(body.url, headers=_HEADERS)
    except httpx.HTTPError as exc:
        raise Upstream(f"player page could not be read: {exc}") from exc

    if page.status_code != 200:
        raise Upstream(f"player page answered {page.status_code}")

    found = _pick(page.text, season=body.season, episode=body.episode)
    if not found:
        raise NotFound("the player page holds nothing playable")

    return ResolveOut(
        streams=[StreamOut(url=one.url, label=one.label, source=one.source) for one in found]
    )


def _pick(html: str, *, season: int | None, episode: int | None) -> tuple[Stream, ...]:
    """The leaf asked for, or everything the page holds.

    A film has no playlist and both numbers are meaningless; a serial has one,
    and the streams of every episode flattened together would hand somebody
    episode one when they asked for nine.
    """
    listed = episodes(html)
    if not listed or (season is None and episode is None):
        return streams(html)

    for leaf in listed:
        if season is not None and leaf.season != season:
            continue
        if episode is not None and leaf.episode != episode:
            continue
        if leaf.streams:
            return leaf.streams

    return streams(html)
