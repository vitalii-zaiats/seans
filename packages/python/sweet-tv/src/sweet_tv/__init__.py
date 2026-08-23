"""sweet.tv's free channels: the list, what is on, and a playable stream.

No account and no login — a uuid the caller invents stands in for one, which is
all the free tier asks for. The package performs no I/O of its own: it talks to
a `Transport`, and `sweet_tv.transports.httpx` is the one it builds when you
supply none.

    from sweet_tv import AsyncSweetTv

    async with AsyncSweetTv() as tv:
        catalogue = await tv.channels()
        stream = await tv.open_stream(catalogue.channels[0].id)

What it does *not* do is pretend a stream URL is an address. `open_stream` hands
back a lease with a session in it that goes stale in minutes — store the channel
id and ask again.
"""

from sweet_tv.client import DEFAULT_TIMEOUT, AsyncSweetTv, SweetTv
from sweet_tv.device import MACOS, PLAYER, WEB_BROWSER, Device
from sweet_tv.errors import (
    HTTPError,
    NetworkError,
    Refused,
    SerializationError,
    SweetTvError,
)
from sweet_tv.jsonread import JsonMap
from sweet_tv.models import (
    ALL_CATEGORY,
    Catalogue,
    Category,
    Channel,
    Programme,
    Schedule,
    Stream,
)
from sweet_tv.site import SWEET, Site, secure
from sweet_tv.transport import AsyncTransport, Request, Response, Transport

__version__ = "0.1.0"

__all__ = [
    "ALL_CATEGORY",
    "DEFAULT_TIMEOUT",
    "MACOS",
    "PLAYER",
    "SWEET",
    "WEB_BROWSER",
    "AsyncSweetTv",
    "AsyncTransport",
    "Catalogue",
    "Category",
    "Channel",
    "Device",
    "HTTPError",
    "JsonMap",
    "NetworkError",
    "Programme",
    "Refused",
    "Request",
    "Response",
    "Schedule",
    "SerializationError",
    "Site",
    "Stream",
    "SweetTv",
    "SweetTvError",
    "Transport",
    "__version__",
    "secure",
]
