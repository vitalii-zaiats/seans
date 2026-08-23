"""Shapes shared by every module's DTOs."""

from pydantic import BaseModel, ConfigDict

# What a JSON document can hold, spelled out rather than left as `Any`. Used by
# the parts of the API that carry a payload they deliberately do not interpret —
# a remote-control command, a device's state — where the alternative is a bare
# `dict` that tells a reader nothing.
type JsonValue = str | int | float | bool | list[JsonValue] | dict[str, JsonValue] | None


class ORMModel(BaseModel):
    """A DTO read straight off a SQLAlchemy row."""

    model_config = ConfigDict(from_attributes=True)


class Page(BaseModel):
    """The envelope every listing uses, so paging looks the same everywhere."""

    total: int
    limit: int
    offset: int
