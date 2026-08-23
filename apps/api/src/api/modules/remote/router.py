"""Driving a box, and hearing what it is doing.

Four endpoints and a clean split of who names whom. A box never names itself —
its session already says which install it is, and a device that could name
itself could name somebody else's. A remote always names the box, and is only
answered for one it is signed in on.

Nothing carries an SSE `id:`. Resumption would mean replaying, and replaying a
command is exactly wrong: an instruction is about *now*, and a television that
missed "play" while its Wi-Fi blinked must not act on it a minute later. State
is a fact rather than an instruction, so the newest one is handed over the
moment a stream opens — which is resumption, for the half where it makes sense.
"""

from collections.abc import AsyncIterator

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from api.core import sse
from api.modules.accounts.deps import CurrentUser
from api.modules.remote.bus import Command, State
from api.modules.remote.deps import CallingDevice, Remote
from api.modules.remote.schemas import (
    CommandIn,
    DeliveryOut,
    DeviceList,
    DeviceOut,
    StateIn,
    StateOut,
)
from api.modules.remote.service import RemoteService

router = APIRouter(tags=["remote"])


@router.get("/devices", response_model=DeviceList)
async def devices(user: CurrentUser, remote: Remote) -> DeviceList:
    """Every box you are signed in on — which is exactly the set you may drive.

    Signing a box in claims it; signing it out gives it up. That is why there is
    no separate list of "my devices" to fall out of step with reality.
    """
    return DeviceList(items=[DeviceOut.of(device) for device in await remote.drivable(user.id)])


@router.post("/device/{public_id}/rpc", response_model=DeliveryOut, status_code=202)
async def send(public_id: str, body: CommandIn, user: CurrentUser, remote: Remote) -> DeliveryOut:
    """Press a button on somebody's television.

    `202`, not `200`: this hands the command to whoever is listening and does
    not wait to hear how it went. `listeners` in the answer is the honest
    version of "did that work" — zero means nobody was connected.
    """
    device = await remote.device_for(public_id, user_id=user.id)
    return DeliveryOut.of(
        await remote.send(device, id=body.id, method=body.method, params=body.params)
    )


@router.get("/device/{public_id}/events")
async def watch(public_id: str, user: CurrentUser, remote: Remote) -> StreamingResponse:
    """A remote watching what a box is doing.

    Opens with whatever the box last said, so a phone that just unlocked has
    something to draw before the next change arrives.
    """
    device = await remote.device_for(public_id, user_id=user.id)
    return _stream(_states(remote, device.id))


@router.get("/device/events")
async def commands(device_id: CallingDevice, remote: Remote) -> StreamingResponse:
    """The box, listening for buttons."""
    return _stream(_commands(remote, device_id))


@router.post("/device/state", status_code=204)
async def report(body: StateIn, device_id: CallingDevice, remote: Remote) -> None:
    """The box saying what it is doing."""
    await remote.report(device_id, body.state)


def _stream(source: AsyncIterator[bytes]) -> StreamingResponse:
    return StreamingResponse(source, media_type="text/event-stream", headers=sse.HEADERS)


async def _commands(remote: RemoteService, device_id: int) -> AsyncIterator[bytes]:
    async with remote.bus.listen(device_id) as events:
        yield sse.comment("open")
        async for event in sse.with_keepalive(events):
            if event is None:
                yield sse.comment("ping")
            elif isinstance(event, Command):
                yield sse.frame("command", _command_json(event))


async def _states(remote: RemoteService, device_id: int) -> AsyncIterator[bytes]:
    async with remote.bus.listen(device_id) as events:
        latest = remote.latest_state(device_id)
        if latest is not None:
            yield sse.frame("state", StateOut.of(latest).model_dump_json())
        yield sse.comment("open")
        async for event in sse.with_keepalive(events):
            if event is None:
                yield sse.comment("ping")
            elif isinstance(event, State):
                yield sse.frame("state", StateOut.of(event).model_dump_json())


def _command_json(command: Command) -> str:
    return CommandIn(
        id=command.id, method=command.method, params=dict(command.params)
    ).model_dump_json()
