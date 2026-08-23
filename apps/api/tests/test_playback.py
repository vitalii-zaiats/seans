"""Reading a player page.

The extraction is a port of `packages/dart/ashdi_finder`, and the fixture is
that package's own — two implementations of one parser, checked against the same
captured page, is the only thing that keeps them honest about each other.
"""

from pathlib import Path

import httpx2
import pytest
from api.main import create_app
from api.modules.playback.extract import episodes, streams

FILM = (Path(__file__).parent / "fixtures_vod_film.html").read_text()

#: A serial's `file`, nested dub → season → episode, as Playerjs writes it.
SERIAL = """
<script>
player = new Playerjs({id:"videoplayer1", file:'[{"title":"Postmodern","folder":[
  {"title":"Сезон 1","folder":[
    {"title":"Серія 1","file":"https://ashdi.vip/s1e1/index.m3u8","id":"1"},
    {"title":"Серія 2","file":"[720p]https://ashdi.vip/s1e2-720/index.m3u8,[1080p]https://ashdi.vip/s1e2-1080/index.m3u8","id":"2"}
  ]},
  {"title":"Сезон 2","folder":[
    {"title":"Серія 1","file":"https://ashdi.vip/s2e1/index.m3u8","id":"3"}
  ]}
]}]'});
</script>
"""


def test_a_film_is_one_stream() -> None:
    found = streams(FILM)

    assert len(found) == 1
    assert found[0].url.endswith("/hls/DK2Xi3aHjuJbhAj6/index.m3u8")
    assert found[0].source == "playerjs"
    # A `/vod/` page plays one file and has no playlist to walk.
    assert episodes(FILM) == ()


def test_a_serial_keeps_its_shape() -> None:
    listed = episodes(SERIAL)

    # Three leaves: S1E1, S1E2, S2E1. The second has two *streams*, not two
    # episodes — a quality list is one leaf.
    assert len(listed) == 3
    first = listed[0]
    assert (first.season, first.episode) == (1, 1)
    # The folder that is not a season named the voices.
    assert first.dub == "Postmodern"
    # The label keeps the whole path, so a flattened stream still says where it
    # came from.
    assert first.streams[0].label == "Postmodern / Сезон 1 / Серія 1"

    last = listed[-1]
    assert (last.season, last.episode) == (2, 1)


def test_qualities_come_back_labelled() -> None:
    second = episodes(SERIAL)[1]

    assert [one.label for one in second.streams] == [
        "Postmodern / Сезон 1 / Серія 2 / 720p",
        "Postmodern / Сезон 1 / Серія 2 / 1080p",
    ]


def test_a_page_with_no_config_is_swept_and_says_so() -> None:
    """Worse than reading the configuration, and better than nothing — but the
    caller should be able to tell which happened."""
    found = streams('<video src="https://ashdi.vip/loose/index.m3u8"></video>')

    assert len(found) == 1
    assert found[0].source == "page-scan"


def test_nothing_playable_is_nothing_rather_than_a_guess() -> None:
    assert streams("<html><body>no player here</body></html>") == ()


@pytest.mark.anyio
async def test_only_players_this_api_reads() -> None:
    """The endpoint takes a URL, so something has to bound it. A page somewhere
    else is a different parser and possibly a different kind of site."""
    app = create_app()
    transport = httpx2.ASGITransport(app=app)
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        answer = await client.post("/playback/resolve", json={"url": "https://example.com/vod/1"})
        assert answer.status_code == 400


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
