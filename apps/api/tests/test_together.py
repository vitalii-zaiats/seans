"""Watching one film in several places.

The three ways in are all exercised on purpose — anonymous, guest, account —
because "a friend can just click the link" is the requirement this feature lives
or dies by, and it is the one an auth-first design quietly breaks.

The streams are driven through `_open` rather than over HTTP for the reason
`CLAUDE.md` gives: `ASGITransport` never returns from `client.stream()` when the
body is endless, and every one of these is.
"""

import asyncio
import json
from collections.abc import AsyncIterator, Iterator
from datetime import timedelta

import httpx2
import pytest
from api.core.models import utcnow
from api.modules.together.deps import BUS, REPORTS
from api.modules.together.models import Member
from api.modules.together.router import _open
from api.modules.together.service import TogetherService
from sqlalchemy.ext.asyncio import AsyncSession

CREDENTIALS = {"email": "vi@example.com", "password": "hunter2hunter2"}


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


def seat(token: str) -> dict[str, str]:
    return {"x-room-token": token}


@pytest.fixture(autouse=True)
def _fresh_process_state() -> Iterator[None]:
    """The bus and the throttle are process-wide on purpose, so a test must not
    inherit another test's listeners or spent tokens."""
    BUS.forget()
    REPORTS.forget()
    yield
    BUS.forget()
    REPORTS.forget()


@pytest.fixture
async def together(db: AsyncSession) -> TogetherService:
    """The same service the routes get, over the test's session."""
    return TogetherService(db, BUS, REPORTS)


async def opened(client: httpx2.AsyncClient, **body: object) -> dict:
    answer = await client.post("/rooms", json=body)
    assert answer.status_code == 201, answer.text
    return answer.json()


FILM = {"kind": "movie", "id": "the-godfather", "title": "Хрещений батько"}


# --- who may open one, and who may get in -------------------------------------


async def test_a_room_opens_for_somebody_who_has_told_us_nothing(
    client: httpx2.AsyncClient,
) -> None:
    room = await opened(client, title="Friday", is_public=True)

    assert room["token"]
    assert room["me"]["is_host"] is True
    # The host holds the code, because the host is the one who sends it to
    # somebody.
    assert len(room["room"]["code"]) == 6
    assert room["room"]["members"] == 1


async def test_a_stranger_gets_in_with_the_code_and_nothing_else(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Friday")

    answer = await client.post("/rooms/join", json={"code": host["room"]["code"]})

    assert answer.status_code == 201
    guest = answer.json()
    assert guest["me"]["is_host"] is False
    assert guest["token"] != host["token"]
    assert guest["room"]["members"] == 2


async def test_a_guest_and_an_account_arrive_the_same_way(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Friday")
    code = host["room"]["code"]

    visitor = (await client.post("/auth/guest")).json()["session"]["token"]
    member = (await client.post("/auth/register", json=CREDENTIALS)).json()["session"]["token"]

    for token in (visitor, member):
        answer = await client.post("/rooms/join", json={"code": code}, headers=auth(token))
        assert answer.status_code == 201

    listed = (await client.get(f"/rooms/{host['room']['id']}")).json()
    assert listed["members"] == 3


async def test_the_name_you_typed_beats_the_one_on_your_account(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Friday")
    token = (await client.post("/auth/register", json=CREDENTIALS)).json()["session"]["token"]

    answer = await client.post(
        "/rooms/join",
        json={"code": host["room"]["code"], "display_name": "Віталік"},
        headers=auth(token),
    )

    assert answer.json()["me"]["name"] == "Віталік"


async def test_signing_back_in_finds_the_same_seat(client: httpx2.AsyncClient) -> None:
    token = (await client.post("/auth/register", json=CREDENTIALS)).json()["session"]["token"]
    answer = await client.post("/rooms", json={"title": "Friday"}, headers=auth(token))
    host = answer.json()

    # The tab was closed and reopened: same account, same room, same code.
    again = (
        await client.post("/rooms/join", json={"code": host["room"]["code"]}, headers=auth(token))
    ).json()

    assert again["me"]["id"] == host["me"]["id"]
    assert again["me"]["is_host"] is True
    # A second seat would have made the host a stranger in their own room.
    assert again["room"]["members"] == 1
    assert again["token"] != host["token"]


async def test_an_unknown_code_is_a_404(client: httpx2.AsyncClient) -> None:
    assert (await client.post("/rooms/join", json={"code": "ZZZZZZ"})).status_code == 404


async def test_a_room_that_is_over_cannot_be_joined(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    await client.delete(f"/rooms/{host['room']['id']}", headers=seat(host["token"]))

    answer = await client.post("/rooms/join", json={"code": host["room"]["code"]})

    assert answer.status_code == 400


# --- the listing --------------------------------------------------------------


async def test_a_public_room_is_listed_with_what_is_playing(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Friday", is_public=True)
    await client.post(
        f"/rooms/{host['room']['id']}/state",
        json={"media": FILM, "position": 61.5, "paused": False},
        headers=seat(host["token"]),
    )

    page = (await client.get("/rooms")).json()

    assert page["total"] == 1
    item = page["items"][0]
    assert item["showing"]["media"]["title"] == "Хрещений батько"
    assert item["showing"]["playback"]["position"] >= 61.5
    # Being listed is the invitation; the code is how one is accepted.
    assert item["code"] == host["room"]["code"]


async def test_a_private_room_is_not_listed(client: httpx2.AsyncClient) -> None:
    await opened(client, title="Just us", is_public=False)

    assert (await client.get("/rooms")).json()["total"] == 0


async def test_a_private_room_keeps_its_code_from_anybody_outside_it(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Just us", is_public=False)

    outside = (await client.get(f"/rooms/{host['room']['id']}")).json()
    inside = (await client.get(f"/rooms/{host['room']['id']}", headers=seat(host["token"]))).json()

    # The title and the poster are fair game — whoever asked was told the id by
    # somebody. The way in is not.
    assert outside["title"] == "Just us"
    assert outside["code"] is None
    assert inside["code"] == host["room"]["code"]


# --- only the host drives -----------------------------------------------------


async def test_a_viewer_cannot_move_the_film(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()

    answer = await client.post(
        f"/rooms/{host['room']['id']}/state",
        json={"media": FILM, "position": 900},
        headers=seat(viewer["token"]),
    )

    assert answer.status_code == 403


async def test_driving_needs_a_seat_at_all(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")

    answer = await client.post(f"/rooms/{host['room']['id']}/state", json={"position": 1})

    assert answer.status_code == 401


async def test_a_seat_in_one_room_does_not_drive_another(client: httpx2.AsyncClient) -> None:
    mine = await opened(client, title="Mine")
    theirs = await opened(client, title="Theirs")

    answer = await client.post(
        f"/rooms/{theirs['room']['id']}/state",
        json={"media": FILM, "position": 5},
        headers=seat(mine["token"]),
    )

    assert answer.status_code == 404


async def test_a_dragged_scrub_bar_is_throttled(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")

    statuses = set()
    for index in range(40):
        answer = await client.post(
            f"/rooms/{host['room']['id']}/state",
            json={"media": FILM, "position": index},
            headers=seat(host["token"]),
        )
        statuses.add(answer.status_code)

    assert statuses == {200, 403}


async def test_a_report_is_the_whole_picture(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    where = f"/rooms/{host['room']['id']}/state"
    await client.post(where, json={"media": FILM, "position": 10}, headers=seat(host["token"]))

    # Nothing is on any more — and last night's title does not linger.
    answer = await client.post(where, json={"position": 0}, headers=seat(host["token"]))

    assert answer.json()["media"] is None


# --- where the film actually is -----------------------------------------------


async def _wind_back(together: TogetherService, public_id: str, seconds: float) -> None:
    """Make the host's last report `seconds` old, without waiting that long."""
    room = await together.rooms.by_public_id(public_id)
    assert room is not None
    room.playback_at = utcnow() - timedelta(seconds=seconds)
    await together.session.commit()


async def test_a_latecomer_is_told_where_the_film_is_now(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    await client.post(
        f"/rooms/{host['room']['id']}/state",
        json={"media": FILM, "position": 100.0, "paused": False},
        headers=seat(host["token"]),
    )
    await _wind_back(together, host["room"]["id"], 30)

    playback = (await client.get(f"/rooms/{host['room']['id']}")).json()["showing"]["playback"]

    # 130, not 100: the position is wound forward to the moment it is handed
    # over, because the reader's clock is not ours to trust.
    assert 130.0 <= playback["position"] < 131.0


async def test_a_paused_film_has_not_moved(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    await client.post(
        f"/rooms/{host['room']['id']}/state",
        json={"media": FILM, "position": 100.0, "paused": True},
        headers=seat(host["token"]),
    )
    await _wind_back(together, host["room"]["id"], 30)

    playback = (await client.get(f"/rooms/{host['room']['id']}")).json()["showing"]["playback"]

    assert playback["position"] == 100.0


# --- leaving and ending -------------------------------------------------------


async def test_a_viewer_leaving_leaves_the_room_standing(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()

    left = await client.post(f"/rooms/{host['room']['id']}/leave", headers=seat(viewer["token"]))

    assert left.status_code == 204
    assert (await client.get(f"/rooms/{host['room']['id']}")).json()["members"] == 1


async def test_the_host_leaving_ends_it_for_everybody(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    await client.post("/rooms/join", json={"code": host["room"]["code"]})

    left = await client.post(f"/rooms/{host['room']['id']}/leave", headers=seat(host["token"]))

    assert left.status_code == 204
    # Anything else leaves a film playing for a group with nobody able to pause
    # it.
    assert (await client.get(f"/rooms/{host['room']['id']}")).status_code == 404


async def test_a_viewer_cannot_end_it(client: httpx2.AsyncClient) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()

    answer = await client.delete(f"/rooms/{host['room']['id']}", headers=seat(viewer["token"]))

    assert answer.status_code == 403


# --- the stream ---------------------------------------------------------------


async def read(stream: AsyncIterator[bytes], *, timeout: float = 2.0) -> str:
    """The next thing an SSE stream puts on the wire."""
    async with asyncio.timeout(timeout):
        return (await anext(stream)).decode()


def body(frame: str) -> dict:
    event, data, _, _ = frame.split("\n")
    return {"event": event.removeprefix("event: "), **json.loads(data.removeprefix("data: "))}


async def stream_for(together: TogetherService, token: str) -> AsyncIterator[bytes]:
    found = await together.seat_for(token)
    assert isinstance(found, Member)
    return await _open(together, found)


async def test_a_stream_opens_with_where_the_film_is(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    await client.post(
        f"/rooms/{host['room']['id']}/state",
        json={"media": FILM, "position": 42.0, "paused": True},
        headers=seat(host["token"]),
    )

    stream = await stream_for(together, host["token"])
    try:
        opening = body(await read(stream))
    finally:
        await stream.aclose()

    assert opening["event"] == "state"
    assert opening["media"]["id"] == "the-godfather"
    assert opening["playback"]["position"] == 42.0


async def test_everybody_hears_the_host(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()

    stream = await stream_for(together, viewer["token"])
    try:
        assert body(await read(stream))["event"] == "state"
        assert await read(stream) == ": open\n\n"
        # Arriving is itself an event, and it goes round the room rather than
        # straight down this stream — so it arrives the way everybody else's
        # does, through the queue, after the stream is open.
        assert body(await read(stream))["event"] == "members"

        await client.post(
            f"/rooms/{host['room']['id']}/state",
            json={"media": FILM, "position": 300.0, "paused": False},
            headers=seat(host["token"]),
        )
        moved = body(await read(stream))
    finally:
        await stream.aclose()

    assert moved["event"] == "state"
    # Not exactly 300: what goes on the wire is already wound forward to the
    # instant it was written, and writing it took a moment.
    assert 300.0 <= moved["playback"]["position"] < 300.1


async def test_the_room_hears_somebody_arrive(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")

    stream = await stream_for(together, host["token"])
    try:
        await read(stream)  # state
        await read(stream)  # : open
        await read(stream)  # members — this stream opening

        await client.post("/rooms/join", json={"code": host["room"]["code"], "display_name": "Оля"})
        arrived = body(await read(stream))
    finally:
        await stream.aclose()

    assert arrived["event"] == "members"
    assert [member["name"] for member in arrived["members"]][-1] == "Оля"
    assert arrived["watching"] == 1


async def test_a_closed_room_says_so_and_then_stops(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()

    stream = await stream_for(together, viewer["token"])
    try:
        await read(stream)  # state
        await read(stream)  # : open
        await read(stream)  # members

        await client.delete(f"/rooms/{host['room']['id']}", headers=seat(host["token"]))
        ending = body(await read(stream))

        assert ending == {"event": "closed", "reason": "host"}
        # Nothing else is coming, and the body ends rather than idling.
        with pytest.raises(StopAsyncIteration):
            await read(stream)
    finally:
        await stream.aclose()


async def test_a_seat_in_a_room_that_ended_is_no_longer_a_seat(
    client: httpx2.AsyncClient,
) -> None:
    host = await opened(client, title="Friday")
    viewer = (await client.post("/rooms/join", json={"code": host["room"]["code"]})).json()
    await client.delete(f"/rooms/{host['room']['id']}", headers=seat(host["token"]))

    # What an `EventSource` gets when it reconnects out of habit — which is what
    # stops it reconnecting forever.
    answer = await client.get(f"/rooms/{host['room']['id']}/events", headers=seat(viewer["token"]))

    assert answer.status_code == 401


async def test_a_stream_is_labelled_so_proxies_leave_it_alone(
    client: httpx2.AsyncClient, together: TogetherService
) -> None:
    host = await opened(client, title="Friday")
    stream = await stream_for(together, host["token"])
    try:
        from api.modules.together.router import _stream

        response = _stream(stream)
    finally:
        await stream.aclose()

    assert response.media_type == "text/event-stream"
    # nginx buffers a stream into uselessness unless told this.
    assert response.headers["x-accel-buffering"] == "no"
