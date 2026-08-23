"""Playlists and segments, relayed.

What is worth testing here is not the piping — httpx does that — but the three
rules that decide whether a request happens at all, and the rewriting that makes
a proxied playlist mean anything.
"""

import httpx2
import pytest
from api.errors import Forbidden, Invalid
from api.main import create_app
from api.modules.stream.playlist import is_playlist, rewrite
from api.modules.stream.targets import allows, target

MASTER = """#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720
https://cdn.ashdi.vip/other/720/index.m3u8
"""

MEDIA = """#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6.0,
seg-1.ts
#EXTINF:6.0,
../elsewhere/seg-2.ts
"""


def test_rewrite_points_every_line_back_at_us() -> None:
    out = rewrite(MASTER, "https://cdn.ashdi.vip/hls/master.m3u8")

    # Relative and absolute lines are both resolved and both come back proxied.
    assert "/stream?url=https%3A%2F%2Fcdn.ashdi.vip%2Fhls%2F360%2Findex.m3u8" in out
    assert "/stream?url=https%3A%2F%2Fcdn.ashdi.vip%2Fother%2F720%2Findex.m3u8" in out
    # The tags themselves are untouched.
    assert "#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360" in out


def test_rewrite_reaches_inside_uri_attributes() -> None:
    """A key or an init segment hides in an attribute, and a player fetches it
    just the same. Missing these is a stream that plays for exactly zero
    seconds."""
    out = rewrite(MEDIA, "https://cdn.ashdi.vip/hls/720/index.m3u8")

    assert 'URI="/stream?url=https%3A%2F%2Fcdn.ashdi.vip%2Fhls%2F720%2Fkey.bin"' in out
    assert 'URI="/stream?url=https%3A%2F%2Fcdn.ashdi.vip%2Fhls%2F720%2Finit.mp4"' in out
    # `..` is resolved against the playlist's own address, not ours.
    assert "%2Fhls%2Felsewhere%2Fseg-2.ts" in out
    assert "#EXTINF:6.0," in out


def test_rewrite_is_relative_so_the_host_does_not_matter() -> None:
    """Every link written back is a path. That is what lets the same answer work
    on localhost, behind a tunnel and on a hostname nobody has bought yet."""
    out = rewrite(MASTER, "https://cdn.ashdi.vip/hls/master.m3u8")

    for line in out.splitlines():
        if line and not line.startswith("#"):
            assert line.startswith("/stream?url=")


@pytest.mark.parametrize(
    ("content_type", "url", "expected"),
    [
        ("application/vnd.apple.mpegurl", "https://h/x", True),
        ("audio/x-mpegURL", "https://h/x", True),
        # Plenty of hosts send this and mean a playlist.
        ("application/octet-stream", "https://h/x.m3u8", True),
        ("application/octet-stream", "https://h/x.m3u8?token=1", True),
        ("video/mp2t", "https://h/seg-1.ts", False),
        (None, "https://h/seg-1.ts", False),
    ],
)
def test_playlist_detection(content_type: str | None, url: str, expected: bool) -> None:
    assert is_playlist(content_type, url) is expected


def test_the_allowlist_fails_closed() -> None:
    with pytest.raises(Forbidden):
        target("https://example.com/x.m3u8", allowed=[])


def test_a_leading_dot_covers_a_domain_and_not_a_lookalike() -> None:
    """The list rule on its own — no name server involved.

    `target` would also resolve the host, which would make this a test of
    whether a CDN happens to be up today."""
    assert allows("cdn.ashdi.vip", [".ashdi.vip"])
    assert allows("ashdi.vip", [".ashdi.vip"])
    assert allows("ashdi.vip", ["ashdi.vip"])

    # The reason a bare suffix match is not enough: this is somebody else's.
    assert not allows("ashdi.vip.example.com", [".ashdi.vip"])
    # An exact entry does not cover what is under it.
    assert not allows("cdn.ashdi.vip", ["ashdi.vip"])
    assert not allows("anything", [])
    assert allows("anything", ["*"])


def test_nothing_private_even_with_a_wildcard() -> None:
    """`*` turns the allowlist off. It does not turn off the network this
    server sits on — a metadata endpoint or a database is one `?url=` away
    otherwise."""
    for url in (
        "http://127.0.0.1:5432/",
        "http://localhost/",
        "http://169.254.169.254/latest/meta-data/",
        "http://10.0.0.5/",
    ):
        with pytest.raises(Forbidden):
            target(url, allowed=["*"])


def test_a_url_that_is_not_one() -> None:
    for url in ("", "not-a-url", "file:///etc/passwd", "ftp://h/x"):
        with pytest.raises(Invalid):
            target(url, allowed=["*"])


@pytest.mark.anyio
async def test_a_refusal_reads_correctly_on_the_wire() -> None:
    """The rules above are only worth as much as the status they produce."""
    app = create_app()
    transport = httpx2.ASGITransport(app=app)
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        blocked = await client.get("/stream", params={"url": "https://example.com/x.m3u8"})
        assert blocked.status_code == 403

        bad = await client.get("/stream", params={"url": "nonsense"})
        assert bad.status_code == 400


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
