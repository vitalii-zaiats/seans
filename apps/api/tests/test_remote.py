"""Driving a box from a phone.

The fixture below is the real journey and not a shortcut: a television announces
itself, a phone signs it in over the pairing dance, and only then does the phone
own something it may drive.
"""

import asyncio
import json
import uuid
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass

import httpx2
import pytest
from api.modules.accounts.service import AccountService
from api.modules.installs.models import Install
from api.modules.installs.service import InstallService
from api.modules.release.service import ReleaseService
from api.modules.remote.adapters import Directory
from api.modules.remote.deps import BUS, THROTTLE
from api.modules.remote.router import _commands, _states, _stream
from api.modules.remote.service import RemoteService
from api.settings import settings
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

CREDENTIALS = {"email": "vi@example.com", "password": "hunter2hunter2"}


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


@dataclass(frozen=True, slots=True)
class Paired:
    """A television and the phone that signed it in."""

    device_id: str
    tv: str
    phone: str


@pytest.fixture(autouse=True)
def _fresh_process_state() -> Iterator[None]:
    """The bus and the throttle are process-wide on purpose, so a test must not
    inherit another test's listeners, snapshots or spent tokens."""
    for reset in _clear:
        reset()
    yield
    for reset in _clear:
        reset()


def _clear_bus() -> None:
    BUS._listeners.clear()
    BUS._state.clear()


_clear = (_clear_bus, THROTTLE.forget)


@pytest.fixture
async def remote(db: AsyncSession) -> RemoteService:
    """The same service the routes get, over the test's session."""
    accounts = AccountService(db)
    installs = InstallService(db, accounts, ReleaseService(settings))
    return RemoteService(Directory(accounts, installs), BUS, THROTTLE)


async def row_id(db: AsyncSession, public_id: str) -> int:
    install = await db.scalar(select(Install).where(Install.public_id == uuid.UUID(public_id)))
    assert install is not None
    return install.id


@pytest.fixture
async def paired(client: httpx2.AsyncClient) -> Paired:
    device_id = str(uuid.uuid4())
    started = await client.post(
        "/init", json={"id": device_id, "platform": "android", "ver": "1.0.0"}
    )
    tv = started.json()["session"]["token"]

    link = (await client.post("/auth/device", headers=auth(tv))).json()
    phone = (await client.post("/auth/register", json=CREDENTIALS)).json()
    await client.post(
        "/auth/device/approve",
        json={"code": link["code"]},
        headers=auth(phone["session"]["token"]),
    )
    collected = (await client.post("/auth/device/collect", json={"secret": link["secret"]})).json()

    return Paired(
        device_id=device_id,
        tv=collected["identity"]["session"]["token"],
        phone=phone["session"]["token"],
    )


# --- who may drive what -------------------------------------------------------


async def test_devices_lists_the_boxes_you_are_signed_in_on(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    answer = await client.get("/devices", headers=auth(paired.phone))

    assert answer.status_code == 200
    items = answer.json()["items"]
    assert [item["id"] for item in items] == [paired.device_id]
    assert items[0]["platform"] == "android"


async def test_a_box_you_never_signed_into_might_as_well_not_exist(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    stranger = (
        await client.post(
            "/auth/register", json={"email": "other@example.com", "password": "hunter2hunter2"}
        )
    ).json()

    answer = await client.post(
        f"/device/{paired.device_id}/rpc",
        json={"id": "1", "method": "play"},
        headers=auth(stranger["session"]["token"]),
    )

    # 404 rather than 403: telling a stranger the device exists is telling them
    # something.
    assert answer.status_code == 404


async def test_driving_needs_an_account(client: httpx2.AsyncClient, paired: Paired) -> None:
    answer = await client.post(
        f"/device/{paired.device_id}/rpc", json={"id": "1", "method": "play"}
    )

    assert answer.status_code == 401


async def test_a_device_id_that_is_not_a_uuid_is_just_not_found(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    answer = await client.post(
        "/device/not-a-uuid/rpc",
        json={"id": "1", "method": "play"},
        headers=auth(paired.phone),
    )

    assert answer.status_code == 404


# --- sending ------------------------------------------------------------------


async def test_a_command_nobody_is_listening_for_says_so(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    answer = await client.post(
        f"/device/{paired.device_id}/rpc",
        json={"id": "cmd-1", "method": "play", "params": {"id": "tt0111161"}},
        headers=auth(paired.phone),
    )

    assert answer.status_code == 202
    assert answer.json() == {"id": "cmd-1", "listeners": 0}


async def test_a_method_name_is_checked_before_anything_happens(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    answer = await client.post(
        f"/device/{paired.device_id}/rpc",
        json={"id": "1", "method": "DROP TABLE"},
        headers=auth(paired.phone),
    )

    assert answer.status_code == 422


async def test_params_have_a_ceiling(client: httpx2.AsyncClient, paired: Paired) -> None:
    answer = await client.post(
        f"/device/{paired.device_id}/rpc",
        json={"id": "1", "method": "play", "params": {"blob": "x" * 5000}},
        headers=auth(paired.phone),
    )

    assert answer.status_code == 422


async def test_a_stuck_key_is_throttled(client: httpx2.AsyncClient, paired: Paired) -> None:
    statuses = set()
    for index in range(40):
        answer = await client.post(
            f"/device/{paired.device_id}/rpc",
            json={"id": str(index), "method": "volume_up"},
            headers=auth(paired.phone),
        )
        statuses.add(answer.status_code)

    assert statuses == {202, 403}


# --- the box's own endpoints --------------------------------------------------


async def test_the_state_endpoint_is_for_a_device_not_a_browser(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    # The phone has an account, but its session was never issued to an install.
    answer = await client.post(
        "/device/state", json={"state": {"playing": True}}, headers=auth(paired.phone)
    )

    assert answer.status_code == 403


async def test_the_state_endpoint_needs_a_session_at_all(
    client: httpx2.AsyncClient,
) -> None:
    assert (await client.post("/device/state", json={"state": {}})).status_code == 401


# --- the stream ---------------------------------------------------------------


async def read(stream: AsyncIterator[bytes], *, timeout: float = 2.0) -> str:
    """The next thing an SSE stream puts on the wire."""
    async with asyncio.timeout(timeout):
        return (await anext(stream)).decode()


async def test_a_box_hears_a_button_press(
    client: httpx2.AsyncClient, paired: Paired, remote: RemoteService, db: AsyncSession
) -> None:
    device_id = await row_id(db, paired.device_id)
    stream = _commands(remote, device_id)
    try:
        assert await read(stream) == ": open\n\n"

        sent = await client.post(
            f"/device/{paired.device_id}/rpc",
            json={"id": "cmd-1", "method": "play", "params": {"id": "tt0111161"}},
            headers=auth(paired.phone),
        )
        assert sent.json()["listeners"] == 1

        frame = await read(stream)
    finally:
        await stream.aclose()

    event, data, _, _ = frame.split("\n")
    assert event == "event: command"
    assert json.loads(data.removeprefix("data: ")) == {
        "id": "cmd-1",
        "method": "play",
        "params": {"id": "tt0111161"},
    }


async def test_a_phone_sees_what_the_box_is_doing(
    client: httpx2.AsyncClient, paired: Paired, remote: RemoteService, db: AsyncSession
) -> None:
    device_id = await row_id(db, paired.device_id)
    stream = _states(remote, device_id)
    try:
        # Nothing said yet, so the stream opens with no snapshot.
        assert await read(stream) == ": open\n\n"

        await client.post(
            "/device/state",
            json={"state": {"playing": True, "title": "Хрещений батько"}},
            headers=auth(paired.tv),
        )

        frame = await read(stream)
    finally:
        await stream.aclose()

    event, data, _, _ = frame.split("\n")
    assert event == "event: state"
    body = json.loads(data.removeprefix("data: "))
    assert body["state"] == {"playing": True, "title": "Хрещений батько"}
    assert body["at"]


async def test_a_phone_that_connects_late_is_told_the_current_state(
    client: httpx2.AsyncClient, paired: Paired, remote: RemoteService, db: AsyncSession
) -> None:
    await client.post("/device/state", json={"state": {"playing": False}}, headers=auth(paired.tv))

    device_id = await row_id(db, paired.device_id)
    stream = _states(remote, device_id)
    try:
        frame = await read(stream)
    finally:
        await stream.aclose()

    event, data, _, _ = frame.split("\n")
    assert event == "event: state"
    assert json.loads(data.removeprefix("data: "))["state"] == {"playing": False}


async def test_a_command_never_reaches_the_stream_meant_for_state(
    client: httpx2.AsyncClient, paired: Paired, remote: RemoteService, db: AsyncSession
) -> None:
    device_id = await row_id(db, paired.device_id)
    stream = _states(remote, device_id)
    try:
        assert await read(stream) == ": open\n\n"

        await client.post(
            f"/device/{paired.device_id}/rpc",
            json={"id": "cmd-1", "method": "play"},
            headers=auth(paired.phone),
        )
        await client.post(
            "/device/state", json={"state": {"playing": True}}, headers=auth(paired.tv)
        )

        # The command went to the same room and was skipped; the next thing this
        # stream sees is the state.
        frame = await read(stream)
    finally:
        await stream.aclose()

    assert frame.startswith("event: state")


async def test_a_stream_is_labelled_so_proxies_leave_it_alone() -> None:
    # Asserted on the response object rather than over HTTP: the body is endless
    # by design, and nothing that opens one ever gets to close it politely.
    async def nothing() -> AsyncIterator[bytes]:
        yield b""

    response = _stream(nothing())

    assert response.media_type == "text/event-stream"
    assert response.headers["cache-control"] == "no-cache"
    # nginx buffers a stream into uselessness unless told this.
    assert response.headers["x-accel-buffering"] == "no"


async def test_an_unpaired_browser_cannot_open_a_box_stream(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    assert (await client.get("/device/events", headers=auth(paired.phone))).status_code == 403


async def test_watching_a_box_that_is_not_yours_is_a_404(
    client: httpx2.AsyncClient, paired: Paired
) -> None:
    stranger = (
        await client.post(
            "/auth/register",
            json={"email": "other@example.com", "password": "hunter2hunter2"},
        )
    ).json()

    answer = await client.get(
        f"/device/{paired.device_id}/events",
        headers=auth(stranger["session"]["token"]),
    )

    assert answer.status_code == 404
