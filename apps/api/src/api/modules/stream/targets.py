"""What may be fetched, and what may never be.

`api.modules.proxy` gets its safety from taking a path rather than a URL. This
module cannot: an HLS tree names its own addresses. So the safety is here, and
it is two rules rather than one.

**An allowlist that fails closed.** Empty means nothing is allowed — a service
that quietly proxies anything the moment somebody forgets to configure it is
worse than one that refuses until told. `["*"]` is available and is a decision
somebody has to make on purpose.

**No private addresses, ever — `*` included.** This runs on a server that can
reach a database, a metadata endpoint and whatever else shares its network, and
`?url=http://169.254.169.254/…` is the oldest trick there is. The allowlist does
not protect against it, because a hostname on the list can resolve wherever its
owner likes.
"""

import ipaddress
import socket
from urllib.parse import SplitResult, urlsplit

from api.errors import Forbidden, Invalid

#: The one entry that turns the allowlist off. Spelled out so a reader of a
#: settings file knows what they are looking at.
ANY = "*"


def target(url: str, *, allowed: list[str]) -> SplitResult:
    """The address to fetch, or a refusal saying which rule stopped it."""
    parts = urlsplit(url.strip())

    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise Invalid("url must be an absolute http(s) URL")

    if not allows(parts.hostname, allowed):
        raise Forbidden(f"host not allowed: {parts.hostname}")

    _refuse_private(parts.hostname)
    return parts


def allows(host: str, allowed: list[str]) -> bool:
    """Exact names, or a leading dot for "this domain and anything under it".

    Public because it is the rule worth testing on its own: [target] cannot be,
    without a working name server and a host that stays registered.

    A CDN spreads a stream over hosts nobody enumerates by hand —
    `.ashdi.vip` covers every one of them without also covering
    `ashdi.vip.example.com`, which a bare suffix match would.
    """
    host = host.lower().rstrip(".")
    for entry in allowed:
        rule = entry.lower().strip()
        if rule == ANY:
            return True
        if rule.startswith("."):
            if host == rule[1:] or host.endswith(rule):
                return True
        elif host == rule:
            return True
    return False


def _refuse_private(host: str) -> None:
    """Refuse anything that resolves inside this network.

    Every address the name has, not just the first: a host that answers with one
    public address and one loopback would otherwise be a way in on the second
    attempt.
    """
    try:
        found = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    except socket.gaierror as exc:
        raise Invalid(f"{host} does not resolve") from exc

    for info in found:
        address = ipaddress.ip_address(info[4][0])
        if not address.is_global or address.is_multicast:
            raise Forbidden(f"{host} resolves to a non-public address")
