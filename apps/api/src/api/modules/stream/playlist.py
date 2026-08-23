"""Rewriting the URLs inside an `.m3u8`, so nested requests come back here.

Without this the endpoint is pointless for HLS. A player would read the master
playlist through us, then go and fetch the variants and segments straight from
the origin — which is exactly the request a browser refuses, and the reason
anybody proxies a playlist in the first place.

The links written back are **relative** (`/stream?url=…`), so this does not care
what address it is reached on: localhost, a tunnel, or a hostname it will be
given next year.
"""

import re
from urllib.parse import quote, urljoin

#: `#EXT-X-KEY`, `#EXT-X-MAP` and `#EXT-X-MEDIA` all hide a URL in an attribute
#: rather than on a line of their own.
_URI_ATTR = re.compile(r'URI="([^"]*)"')

#: Where a rewritten link points. One place, so the route and the rewriter
#: cannot drift apart.
PATH = "/stream"


def is_playlist(content_type: str | None, url: str) -> bool:
    """Whether this response is a playlist rather than media.

    The content type first, because it is what the origin says it is sending;
    the extension second, because plenty of them send `application/octet-stream`
    and mean `.m3u8`.
    """
    if content_type and "mpegurl" in content_type.lower():
        return True
    return url.split("?", 1)[0].lower().endswith(".m3u8")


def proxied(url: str) -> str:
    return f"{PATH}?url={quote(url, safe='')}"


def rewrite(text: str, base_url: str) -> str:
    """Every URL in [text] pointed back here, resolved against [base_url].

    `base_url` is the address the playlist was *finally* fetched from — after
    redirects — because that is what its relative lines are relative to.
    """
    lines = []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            lines.append(line)
        elif stripped.startswith("#"):
            lines.append(
                _URI_ATTR.sub(lambda m: f'URI="{proxied(urljoin(base_url, m.group(1)))}"', line)
            )
        else:
            lines.append(proxied(urljoin(base_url, stripped)))

    return "\n".join(lines) + "\n"
