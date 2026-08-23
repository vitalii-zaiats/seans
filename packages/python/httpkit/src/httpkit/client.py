"""httpx clients that rotate proxies and back off when told to slow down.

The retry policy is one object shared by both transports, so the sync and async
paths can't drift apart on what "retry" means — only on how they wait.
"""

import asyncio
import random
import threading
import time
from collections.abc import Mapping
from dataclasses import dataclass

import httpx

from httpkit.proxies import ProxyPool

# Worth another go on a different exit IP.
RETRY_STATUS = frozenset({408, 425, 429, 500, 502, 503, 504})

DEFAULT_RETRIES = 3
DEFAULT_BACKOFF = 1.0
MAX_BACKOFF = 30.0
MAX_CONNECTIONS = 20


@dataclass(frozen=True, slots=True)
class RetryPolicy:
    """What to retry and how long to wait — no I/O, so both transports share it."""

    retries: int = DEFAULT_RETRIES
    backoff: float = DEFAULT_BACKOFF

    def worth_retrying(self, status: int) -> bool:
        return status in RETRY_STATUS

    def delay(self, attempt: int) -> float:
        """Exponential, with jitter so parallel workers don't retry in lockstep."""
        capped = min(self.backoff * 2.0**attempt, float(MAX_BACKOFF))
        jitter: float = random.uniform(0.7, 1.3)
        return capped * jitter

    def wait_for(self, response: httpx.Response, attempt: int) -> float:
        """Honour `Retry-After: <seconds>`; the HTTP-date form falls back to backoff."""
        value = response.headers.get("retry-after")
        if value:
            try:
                return min(float(value), float(MAX_BACKOFF))
            except ValueError:
                pass
        return self.delay(attempt)


class _Rotation[TransportT]:
    """Hands out the next transport. Thread-safe because workers share a client."""

    def __init__(self, transports: list[TransportT]) -> None:
        self._transports = transports
        self._index = 0
        self._lock = threading.Lock()

    def next(self) -> TransportT:
        if len(self._transports) == 1:
            return self._transports[0]
        with self._lock:
            transport = self._transports[self._index % len(self._transports)]
            self._index += 1
        return transport

    def all(self) -> list[TransportT]:
        return self._transports


class RetryingTransport(httpx.BaseTransport):
    """Picks the next proxy per attempt and retries the statuses worth retrying.

    Living at the transport layer means every caller gets this without changing
    a single call site.
    """

    def __init__(
        self, transports: list[httpx.BaseTransport], policy: RetryPolicy | None = None
    ) -> None:
        self._rotation = _Rotation[httpx.BaseTransport](transports)
        self._policy = policy or RetryPolicy()

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        for attempt in range(self._policy.retries + 1):
            last = attempt == self._policy.retries

            try:
                response = self._rotation.next().handle_request(request)
            except httpx.TransportError:
                if last:
                    raise
                time.sleep(self._policy.delay(attempt))
                continue

            if not last and self._policy.worth_retrying(response.status_code):
                delay = self._policy.wait_for(response, attempt)
                response.close()
                time.sleep(delay)
                continue

            return response

        raise httpx.TransportError("retries exhausted")  # pragma: no cover

    def close(self) -> None:
        for transport in self._rotation.all():
            transport.close()


class AsyncRetryingTransport(httpx.AsyncBaseTransport):
    """The same policy, awaited."""

    def __init__(
        self, transports: list[httpx.AsyncBaseTransport], policy: RetryPolicy | None = None
    ) -> None:
        self._rotation = _Rotation[httpx.AsyncBaseTransport](transports)
        self._policy = policy or RetryPolicy()

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        for attempt in range(self._policy.retries + 1):
            last = attempt == self._policy.retries

            try:
                response = await self._rotation.next().handle_async_request(request)
            except httpx.TransportError:
                if last:
                    raise
                await asyncio.sleep(self._policy.delay(attempt))
                continue

            if not last and self._policy.worth_retrying(response.status_code):
                delay = self._policy.wait_for(response, attempt)
                await response.aclose()
                await asyncio.sleep(delay)
                continue

            return response

        raise httpx.TransportError("retries exhausted")  # pragma: no cover

    async def aclose(self) -> None:
        for transport in self._rotation.all():
            await transport.aclose()


def _limits(proxy: ProxyPool | None) -> httpx.Limits:
    return httpx.Limits(
        # No keep-alive when proxying: a rotating gateway hands out a new exit IP
        # per connection, so reusing one would pin us to the address we just got
        # rate-limited on.
        max_keepalive_connections=0 if proxy else MAX_CONNECTIONS,
        max_connections=MAX_CONNECTIONS,
    )


def build_client(
    *,
    headers: Mapping[str, str] | None = None,
    timeout: float = 20.0,
    proxy: ProxyPool | None = None,
    retries: int = DEFAULT_RETRIES,
    backoff: float = DEFAULT_BACKOFF,
    follow_redirects: bool = True,
) -> httpx.Client:
    """A client that goes through `proxy` (if given) and retries 429s."""
    limits = _limits(proxy)
    transports: list[httpx.BaseTransport] = (
        [httpx.HTTPTransport(proxy=url, limits=limits) for url in proxy.urls]
        if proxy
        else [httpx.HTTPTransport(limits=limits)]
    )
    return httpx.Client(
        headers=dict(headers or {}),
        timeout=timeout,
        follow_redirects=follow_redirects,
        transport=RetryingTransport(transports, RetryPolicy(retries, backoff)),
    )


def build_async_client(
    *,
    headers: Mapping[str, str] | None = None,
    timeout: float = 20.0,
    proxy: ProxyPool | None = None,
    retries: int = DEFAULT_RETRIES,
    backoff: float = DEFAULT_BACKOFF,
    follow_redirects: bool = True,
) -> httpx.AsyncClient:
    limits = _limits(proxy)
    transports: list[httpx.AsyncBaseTransport] = (
        [httpx.AsyncHTTPTransport(proxy=url, limits=limits) for url in proxy.urls]
        if proxy
        else [httpx.AsyncHTTPTransport(limits=limits)]
    )
    return httpx.AsyncClient(
        headers=dict(headers or {}),
        timeout=timeout,
        follow_redirects=follow_redirects,
        transport=AsyncRetryingTransport(transports, RetryPolicy(retries, backoff)),
    )
