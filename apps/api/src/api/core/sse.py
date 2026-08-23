"""Server-sent events: the framing, and the one trick that keeps them alive.

Infrastructure rather than anybody's domain, which is why it lives here: two
modules want it — a remote watching a box, a room watching a film together —
and neither may import the other.

SSE rather than a websocket because of what these connections have to survive. A
television holds one for months across sleeping Wi-Fi and a router that reboots
at 4am — and an `EventSource` reconnects by itself, where a socket is ours to
notice, back off and rebuild. What we give up is sending *to* the server on the
same connection, and nothing here needs to: a box posts its state, a remote
posts a command, a host posts where the film has got to.
"""

import asyncio
from collections.abc import AsyncIterator

#: How long a quiet stream waits before saying something. Proxies and phone
#: radios drop a connection that has been silent for a minute or two; a comment
#: costs three bytes and is discarded by every client.
KEEPALIVE = 20.0

#: What nginx needs to be told, or it buffers the stream into uselessness.
HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}


def frame(event: str, data: str) -> bytes:
    """One named event. No `id:` on purpose — see `router`."""
    return f"event: {event}\ndata: {data}\n\n".encode()


def comment(text: str) -> bytes:
    """A line every client ignores, which is exactly what a keepalive is."""
    return f": {text}\n\n".encode()


async def with_keepalive[T](source: AsyncIterator[T]) -> AsyncIterator[T | None]:
    """Yields what `source` yields, and `None` whenever it has gone quiet.

    The wait is deliberately `asyncio.wait` rather than `wait_for`: a timeout
    there would cancel the pull, and cancelling `anext` on an async generator
    leaves it in a state it never recovers from.
    """
    pending = asyncio.ensure_future(anext(source))
    try:
        while True:
            done, _ = await asyncio.wait({pending}, timeout=KEEPALIVE)
            if not done:
                yield None
                continue

            item = pending.result()
            pending = asyncio.ensure_future(anext(source))
            yield item
    finally:
        pending.cancel()
