"""The way in: a typed client for the public kinostrain.com content API.

The API needs no credentials. Neither client performs I/O itself — each talks
to a transport, so nothing here has an opinion about httpx, retries or proxies.
Bring nothing and you get httpx:

    from kinostrain import ContentType, KinostrainApi

    with KinostrainApi() as api:
        page = api.catalog(type=ContentType.MOVIE, page=1)

    async with AsyncKinostrainApi() as api:
        page = await api.catalog(type=ContentType.MOVIE, page=1)

Every method raises a `KinostrainError` subclass on failure: `HTTPError` for a
non-2xx status, `NetworkError` when the request never completed,
`SerializationError` when the payload no longer matches the expected shape.

**Why this package exists in Python at all:** the API answers
`access-control-allow-origin: https://kinostrain.com`, so a browser on any
other origin is blocked by CORS. Server-side there is no such problem — this
client is what a proxy of your own calls.
"""

import json as jsonlib
from collections.abc import Mapping, Sequence
from types import TracebackType
from typing import Any
from urllib.parse import urlencode

from kinostrain import calls
from kinostrain.calls import MIN_QUERY_LENGTH, Call
from kinostrain.errors import HTTPError, KinostrainError, NetworkError, SerializationError
from kinostrain.jsonread import JsonMap
from kinostrain.models import (
    CatalogFilters,
    ContentCard,
    ContentDetails,
    ContentType,
    Page,
    Person,
    SearchResult,
)
from kinostrain.transport import AsyncTransport, Request, Response, Transport

DEFAULT_BASE_URL = "https://api.kinostrain.com/api"
DEFAULT_TIMEOUT = 20.0

#: What a browser on the site sends. Upstream does not check it today — a plain
#: curl works — but it costs nothing, so pass it as `headers=` if that changes.
SITE_HEADERS: Mapping[str, str] = {
    "Origin": "https://kinostrain.com",
    "Referer": "https://kinostrain.com/",
}

#: Enough of a failing body to tell what happened, without filling a log line.
_BODY_CLIP = 512


class _Client:
    """Where a call goes and how its answer is read — shared by both clients."""

    def __init__(
        self,
        *,
        base_url: str = DEFAULT_BASE_URL,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        #: Root every path is appended to. A trailing slash is ignored.
        self.base_url = base_url.rstrip("/")
        self._headers: Mapping[str, str] = {"Accept": "application/json", **(headers or {})}

    def url_for(self, path: str, query: Mapping[str, str | None] | None = None) -> str:
        """The absolute URL for `path`, dropping query entries that are `None`."""
        params = [(key, value) for key, value in (query or {}).items() if value is not None]
        url = f"{self.base_url}{path}"
        return f"{url}?{urlencode(params)}" if params else url

    def _request(self, call: Call[Any]) -> Request:
        headers = self._headers
        body: bytes | None = None
        if call.body is not None:
            headers = {**headers, "Content-Type": "application/json"}
            body = jsonlib.dumps(call.body, ensure_ascii=False).encode()
        return Request(
            method=call.method,
            url=self.url_for(call.path, call.query),
            headers=headers,
            body=body,
        )

    def _read[T](self, call: Call[T], url: str, response: Response) -> T:
        # `Response.text` decodes as UTF-8 whatever the adapter saw: the API
        # answers `application/json` with no charset, and a latin-1 fallback
        # would mangle every Cyrillic title.
        text = response.text

        if not response.is_success:
            clipped = text if len(text) <= _BODY_CLIP else f"{text[:_BODY_CLIP]}…"
            raise HTTPError(response.status_code, url, body=clipped)

        try:
            decoded = jsonlib.loads(text)
        except ValueError as exc:
            raise SerializationError(f"response from {url} is not valid JSON", exc) from exc
        if not isinstance(decoded, dict):
            raise SerializationError(
                f"expected a JSON object from {url}, got {type(decoded).__name__}"
            )
        return call.parse(decoded)


class KinostrainApi(_Client):
    """Blocking client for the kinostrain.com content API.

    Pass a `transport` to bring your own network stack — retries, proxies, a
    test double. Without one the client builds an httpx transport and `timeout`
    applies to it; with one, the timeout is that transport's business.

    `close()` closes the transport. Skip it when the transport is shared with
    other code — closing is the owner's job.
    """

    def __init__(
        self,
        transport: Transport | None = None,
        *,
        base_url: str = DEFAULT_BASE_URL,
        headers: Mapping[str, str] | None = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        super().__init__(base_url=base_url, headers=headers)
        if transport is None:
            # Imported here rather than at module scope: httpx is the default,
            # but nothing in the core modules touches it, so a caller who
            # brings their own transport never loads it.
            from kinostrain.transports.httpx import HttpxTransport

            transport = HttpxTransport(timeout=timeout)
        self._transport = transport

    def catalog(
        self,
        *,
        type: ContentType | None = None,
        page: int | None = None,
        genres: Sequence[str] | None = None,
        year: str | None = None,
    ) -> Page[ContentCard]:
        """Paged list of content, optionally narrowed by section, genre and year.

        `genres` and `year` take **slugs** from `catalog_filters()`, not display
        names — `bojovik`, `2006-2010`. Only single-genre filtering was observed
        upstream; several values are sent comma-separated, which the API may or
        may not honour.
        """
        return self._perform(calls.catalog(type=type, page=page, genres=genres, year=year))

    def catalog_filters(self) -> CatalogFilters:
        """Genre and year options per section, plus per-section title counts.

        Static enough to cache for the session — it changes only when a genre
        is added.
        """
        return self._perform(calls.catalog_filters())

    def trending(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """Currently trending titles, richer than catalog cards
        (`short_description`, `country`, wide artwork). Not paginated."""
        return self._perform(calls.trending(type=type))

    def slider(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """Hero-slider titles, with `trailer_youtube_id` and `age_restrictions`
        filled in. Not paginated."""
        return self._perform(calls.slider(type=type))

    def search(self, query: str, *, limit: int | None = None) -> tuple[SearchResult, ...]:
        """Titles matching `query`.

        The endpoint answers nothing at all below two characters, so a shorter
        query short-circuits here rather than costing a round trip — which is
        what makes this safe to call on every keystroke.

        `limit` caps the result count; the server's own default is 10. There is
        no pagination and no `meta`, so what comes back is all there is.
        """
        trimmed = query.strip()
        if len(trimmed) < MIN_QUERY_LENGTH:
            return ()
        return self._perform(calls.search(trimmed, limit=limit))

    def persons(self, *, page: int | None = None) -> Page[Person]:
        """Paged directory of actors and directors."""
        return self._perform(calls.persons(page=page))

    def content(self, slug: str, *, season: int | None = None) -> ContentDetails:
        """Full detail payload for one title, addressed by its slug.

        A series lists **every** season it ever had, but fills in the episodes
        and players of only one. Pass `season` to fill in a different one — the
        others come back empty either way, so an empty season means "not
        fetched yet", never "nothing to watch". `Season.is_loaded` tells them
        apart.

        Raises `HTTPError` with `is_not_found` for an unknown slug.
        """
        return self._perform(calls.content(slug, season=season))

    def cards(self, slugs: Sequence[str]) -> tuple[ContentCard, ...]:
        """Cards for several slugs in one round trip — what the site uses to
        render a stored watchlist.

        These carry `average_rating` and `ratings_count` on top of the usual
        card. The response preserves neither the requested order nor an entry
        for every slug.
        """
        if not slugs:
            return ()
        return self._perform(calls.cards(slugs))

    def comments(self, content_id: int, *, page: int | None = None) -> Page[JsonMap]:
        """Paged comments for a title, addressed by its **numeric**
        `ContentDetails.id` — this endpoint does not accept the slug.

        Entries come back as raw JSON maps: every captured response had an
        empty `data` list, so the comment shape could not be verified and is
        deliberately not guessed at. Inspect one to learn the real fields, then
        promote it to a typed model.
        """
        return self._perform(calls.comments(content_id, page=page))

    def close(self) -> None:
        """Closes the transport."""
        self._transport.close()

    def __enter__(self) -> "KinostrainApi":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self.close()

    def _perform[T](self, call: Call[T]) -> T:
        request = self._request(call)
        try:
            response = self._transport.send(request)
        except KinostrainError:
            raise
        except Exception as exc:
            raise NetworkError(request.url, exc) from exc
        return self._read(call, request.url, response)


class AsyncKinostrainApi(_Client):
    """The same client, awaited.

    Pass a `transport` to bring your own network stack. Without one the client
    builds an httpx transport and `timeout` applies to it; with one, the
    timeout is that transport's business.

    `aclose()` closes the transport. Skip it when the transport is shared with
    other code — closing is the owner's job.
    """

    def __init__(
        self,
        transport: AsyncTransport | None = None,
        *,
        base_url: str = DEFAULT_BASE_URL,
        headers: Mapping[str, str] | None = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        super().__init__(base_url=base_url, headers=headers)
        if transport is None:
            from kinostrain.transports.httpx import AsyncHttpxTransport

            transport = AsyncHttpxTransport(timeout=timeout)
        self._transport = transport

    async def catalog(
        self,
        *,
        type: ContentType | None = None,
        page: int | None = None,
        genres: Sequence[str] | None = None,
        year: str | None = None,
    ) -> Page[ContentCard]:
        """Paged list of content, optionally narrowed by section, genre and year.

        `genres` and `year` take **slugs** from `catalog_filters()`, not display
        names — `bojovik`, `2006-2010`.
        """
        return await self._perform(calls.catalog(type=type, page=page, genres=genres, year=year))

    async def catalog_filters(self) -> CatalogFilters:
        """Genre and year options per section, plus per-section title counts.

        Static enough to cache for the session.
        """
        return await self._perform(calls.catalog_filters())

    async def trending(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """Currently trending titles, richer than catalog cards. Not paginated."""
        return await self._perform(calls.trending(type=type))

    async def slider(self, *, type: ContentType | None = None) -> tuple[ContentCard, ...]:
        """Hero-slider titles, with `trailer_youtube_id` and `age_restrictions`
        filled in. Not paginated."""
        return await self._perform(calls.slider(type=type))

    async def search(self, query: str, *, limit: int | None = None) -> tuple[SearchResult, ...]:
        """Titles matching `query`.

        Anything below two characters short-circuits here rather than costing a
        round trip — the endpoint answers nothing at all for those — which is
        what makes this safe to call on every keystroke.
        """
        trimmed = query.strip()
        if len(trimmed) < MIN_QUERY_LENGTH:
            return ()
        return await self._perform(calls.search(trimmed, limit=limit))

    async def persons(self, *, page: int | None = None) -> Page[Person]:
        """Paged directory of actors and directors."""
        return await self._perform(calls.persons(page=page))

    async def content(self, slug: str, *, season: int | None = None) -> ContentDetails:
        """Full detail payload for one title, addressed by its slug.

        A series lists **every** season but fills in the episodes and players of
        only one; pass `season` to fill in a different one. An empty season
        means "not fetched yet", never "nothing to watch" — `Season.is_loaded`
        tells them apart.

        Raises `HTTPError` with `is_not_found` for an unknown slug.
        """
        return await self._perform(calls.content(slug, season=season))

    async def cards(self, slugs: Sequence[str]) -> tuple[ContentCard, ...]:
        """Cards for several slugs in one round trip.

        These carry `average_rating` and `ratings_count` on top of the usual
        card, and preserve neither the requested order nor an entry per slug.
        """
        if not slugs:
            return ()
        return await self._perform(calls.cards(slugs))

    async def comments(self, content_id: int, *, page: int | None = None) -> Page[JsonMap]:
        """Paged comments, addressed by the **numeric** `ContentDetails.id`.

        Entries come back as raw JSON maps — every captured response was empty,
        so the shape is deliberately not guessed at.
        """
        return await self._perform(calls.comments(content_id, page=page))

    async def aclose(self) -> None:
        """Closes the transport."""
        await self._transport.aclose()

    async def __aenter__(self) -> "AsyncKinostrainApi":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()

    async def _perform[T](self, call: Call[T]) -> T:
        request = self._request(call)
        try:
            response = await self._transport.send(request)
        except KinostrainError:
            raise
        except Exception as exc:
            raise NetworkError(request.url, exc) from exc
        return self._read(call, request.url, response)
