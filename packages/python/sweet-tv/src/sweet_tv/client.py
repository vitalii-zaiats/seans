"""sweet.tv's free channels: what there is, what is on, and how to play it.

No account anywhere. What stands in for one is a `Device` — a uuid the caller
invents and keeps. Channels that are not free will not open through this, and
the client says so rather than pretending.

**Why this exists in Python.** Of the three hosts, only `sweet.tv` — the one
serving the catalogue — sends no CORS headers at all, so a browser cannot read
the channel list and something server-side has to. The rest (`api.sweet.tv`,
`static.sweet.tv`, and the ad-stitching host the stream lives on) all answer
`access-control-allow-origin: *`, so the video itself does not need relaying and
should not be: proxying it would cost bandwidth to fix a problem nobody has.
"""

import json as jsonlib
from collections.abc import Mapping
from contextlib import suppress
from datetime import date
from types import TracebackType
from typing import Any

from sweet_tv.device import Device
from sweet_tv.errors import HTTPError, NetworkError, Refused, SerializationError, SweetTvError
from sweet_tv.jsonread import JsonMap
from sweet_tv.models import Catalogue, Programme, Schedule, Stream
from sweet_tv.site import SWEET, Site
from sweet_tv.transport import AsyncTransport, Request, Response, Transport

DEFAULT_TIMEOUT = 20.0

#: Enough of a failing body to tell what happened, without filling a log line.
_BODY_CLIP = 512


class _Client:
    """Where a call goes and how its answer is read — shared by both clients."""

    def __init__(self, device: Device | None = None, *, site: Site = SWEET) -> None:
        self.device = device or Device()
        self.site = site

    # The catalogue host wants the literal string `web` here rather than the
    # five-number device line the stream API wants. Two different headers with
    # one name, which is why neither is a constant on the device.
    def _list_headers(self) -> Mapping[str, str]:
        return {"x-device": "web"}

    def _post_headers(self) -> Mapping[str, str]:
        return {
            "content-type": "application/json",
            "x-accept-language": self.site.language,
            "x-device": self.device.header,
            "x-device-id": self.device.uuid,
            # Sent because their own player sends it. Measured not to change the
            # answer today — the stream opens without it — but it costs nothing
            # and is the header a service like this starts checking first.
            "referer": f"{self.site.site}/",
        }

    def _get(self, url: str, headers: Mapping[str, str]) -> Request:
        return Request(method="GET", url=url, headers=headers)

    def _post(self, url: str, body: JsonMap) -> Request:
        return Request(
            method="POST",
            url=url,
            headers=self._post_headers(),
            body=jsonlib.dumps(body).encode(),
        )

    def _stream_body(self, channel_id: int) -> JsonMap:
        return {
            "channel_id": channel_id,
            "multistream": True,
            "uuid": self.device.uuid,
            "consent": None,
            "accept_scheme": ["HTTP_HLS"],
        }

    def _read(self, response: Response, url: str) -> Any:
        # UTF-8 whatever the adapter saw: the API answers `application/json`
        # with no charset, and a latin-1 guess mangles every Ukrainian title.
        text = response.text

        if not response.is_success:
            clipped = text if len(text) <= _BODY_CLIP else f"{text[:_BODY_CLIP]}…"
            raise HTTPError(response.status_code, url, body=clipped)

        try:
            return jsonlib.loads(text)
        except ValueError as exc:
            raise SerializationError(f"response from {url} is not valid JSON", exc) from exc

    def _object(self, response: Response, url: str) -> JsonMap:
        decoded = self._read(response, url)
        if not isinstance(decoded, dict):
            raise SerializationError(
                f"expected a JSON object from {url}, got {type(decoded).__name__}"
            )
        return decoded

    def _schedule(self, response: Response, url: str) -> Schedule:
        decoded = self._read(response, url)
        if not isinstance(decoded, list):
            raise SerializationError(
                f"expected a JSON array from {url}, got {type(decoded).__name__}"
            )
        return Schedule(
            tuple(Programme.from_json(item) for item in decoded if isinstance(item, Mapping))
        )

    def _stream(self, json: JsonMap, url: str) -> Stream:
        result = json.get("result")
        if result != "OK":
            raise Refused(result if isinstance(result, str) else None, url)

        stream = Stream.from_json(json)
        if not stream.url:
            raise SerializationError(f"response from {url} carries no stream address")
        return stream


class SweetTv(_Client):
    """Blocking client.

    ```python
    with SweetTv() as tv:
        catalogue = tv.channels()
        stream = tv.open_stream(catalogue.channels[0].id)
    ```

    Pass a `device` to keep the same identity across restarts; without one a
    fresh uuid is invented, and to the service that is a different box.
    """

    def __init__(
        self,
        transport: Transport | None = None,
        *,
        device: Device | None = None,
        site: Site = SWEET,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        super().__init__(device, site=site)
        if transport is None:
            # Imported here, not at module scope: httpx is the default, but
            # nothing in the core touches it, so a caller who brings their own
            # transport never loads it.
            from sweet_tv.transports.httpx import HttpxTransport

            transport = HttpxTransport(timeout=timeout)
        self._transport = transport

    def channels(self) -> Catalogue:
        """Every free channel, with its categories.

        The one call that a browser cannot make for itself.
        """
        url = self.site.channel_list()
        return Catalogue.from_json(
            self._object(self._send(self._get(url, self._list_headers())), url)
        )

    def schedule(self, channel_id: int, day: date) -> Schedule:
        """One channel's programmes for one day.

        A separate file per channel per day, so this is one small request rather
        than a slice of a large one — which is what makes it reasonable to ask
        for the channel somebody is looking at and no others.
        """
        url = self.site.schedule(channel_id, day)
        return self._schedule(self._send(self._get(url, {})), url)

    def open_stream(self, channel_id: int) -> Stream:
        """Ask for a playable address.

        Raises `Refused` with `needs_account` for a channel outside the free
        tier — this package has no account to offer it.
        """
        url = self.site.open_stream()
        return self._stream(
            self._object(self._send(self._post(url, self._stream_body(channel_id))), url), url
        )

    def close_stream(self, stream_id: int) -> None:
        """Tell the service the stream is done with.

        Best effort, and ignorable: without an account it answers `NoAuth` and
        the lease expires on its own. A failure here is never worth showing.
        """
        url = self.site.close_stream()
        with suppress(SweetTvError):
            self._object(self._send(self._post(url, {"stream_id": stream_id})), url)

    def close(self) -> None:
        self._transport.close()

    def __enter__(self) -> "SweetTv":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self.close()

    def _send(self, request: Request) -> Response:
        try:
            return self._transport.send(request)
        except SweetTvError:
            raise
        except Exception as exc:
            raise NetworkError(request.url, exc) from exc


class AsyncSweetTv(_Client):
    """The same client, awaited — what a FastAPI service wants."""

    def __init__(
        self,
        transport: AsyncTransport | None = None,
        *,
        device: Device | None = None,
        site: Site = SWEET,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        super().__init__(device, site=site)
        if transport is None:
            from sweet_tv.transports.httpx import AsyncHttpxTransport

            transport = AsyncHttpxTransport(timeout=timeout)
        self._transport = transport

    async def channels(self) -> Catalogue:
        """Every free channel, with its categories."""
        url = self.site.channel_list()
        return Catalogue.from_json(
            self._object(await self._send(self._get(url, self._list_headers())), url)
        )

    async def schedule(self, channel_id: int, day: date) -> Schedule:
        """One channel's programmes for one day."""
        url = self.site.schedule(channel_id, day)
        return self._schedule(await self._send(self._get(url, {})), url)

    async def open_stream(self, channel_id: int) -> Stream:
        """Ask for a playable address. Raises `Refused` for a paid channel."""
        url = self.site.open_stream()
        return self._stream(
            self._object(await self._send(self._post(url, self._stream_body(channel_id))), url),
            url,
        )

    async def close_stream(self, stream_id: int) -> None:
        """Best effort — see `SweetTv.close_stream`."""
        url = self.site.close_stream()
        with suppress(SweetTvError):
            self._object(await self._send(self._post(url, {"stream_id": stream_id})), url)

    async def aclose(self) -> None:
        await self._transport.aclose()

    async def __aenter__(self) -> "AsyncSweetTv":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        await self.aclose()

    async def _send(self, request: Request) -> Response:
        try:
            return await self._transport.send(request)
        except SweetTvError:
            raise
        except Exception as exc:
            raise NetworkError(request.url, exc) from exc
