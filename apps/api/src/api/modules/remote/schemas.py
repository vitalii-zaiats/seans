"""What the remote endpoints take and hand back."""

import json
from collections.abc import Mapping
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from api.core.schemas import JsonValue
from api.modules.remote.bus import State
from api.modules.remote.ports import Device
from api.modules.remote.service import Delivery

#: A command is a button press, not a file upload.
MAX_PARAMS_BYTES = 4096
#: A state is a screenful of facts, not a catalogue.
MAX_STATE_BYTES = 16_384


def _within(value: Mapping[str, JsonValue], limit: int, what: str) -> Mapping[str, JsonValue]:
    if len(json.dumps(value).encode()) > limit:
        raise ValueError(f"{what} must be under {limit} bytes")
    return value


class CommandIn(BaseModel):
    """One button press.

    `id` is the remote's own, and comes back in the answer — without it a remote
    cannot tell a command that was lost from one that was ignored, and cannot
    safely resend.
    """

    id: str = Field(min_length=1, max_length=64)
    method: str = Field(min_length=1, max_length=64, pattern=r"^[a-z][a-z0-9_.]*$")
    params: dict[str, JsonValue] = Field(default_factory=dict)

    @field_validator("params")
    @classmethod
    def _small(cls, value: dict[str, JsonValue]) -> dict[str, JsonValue]:
        return dict(_within(value, MAX_PARAMS_BYTES, "params"))


class DeliveryOut(BaseModel):
    id: str
    #: How many streams were open on that box. Zero means nobody heard it —
    #: which is not the same as the box refusing.
    listeners: int

    @classmethod
    def of(cls, delivery: Delivery) -> "DeliveryOut":
        return cls(id=delivery.id, listeners=delivery.listeners)


class StateIn(BaseModel):
    """What the box is doing. The server does not interpret it."""

    state: dict[str, JsonValue] = Field(default_factory=dict)

    @field_validator("state")
    @classmethod
    def _small(cls, value: dict[str, JsonValue]) -> dict[str, JsonValue]:
        return dict(_within(value, MAX_STATE_BYTES, "state"))


class StateOut(BaseModel):
    at: datetime
    state: dict[str, JsonValue]

    @classmethod
    def of(cls, state: State) -> "StateOut":
        return cls(at=state.at, state=dict(state.data))


class DeviceOut(BaseModel):
    id: str
    platform: str
    version: str
    last_seen_at: datetime

    @classmethod
    def of(cls, device: Device) -> "DeviceOut":
        return cls(
            id=device.public_id,
            platform=device.platform,
            version=device.version,
            last_seen_at=device.last_seen_at,
        )


class DeviceList(BaseModel):
    items: list[DeviceOut]
