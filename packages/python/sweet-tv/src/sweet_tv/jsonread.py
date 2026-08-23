"""Tolerant readers, the same shape as the ones in `kinostrain`.

`*_or_none` returns `None` for a missing field, a JSON `null`, or a value of the
wrong type; `require_*` raises `SerializationError` naming the field, because a
missing required field means the model can no longer be trusted.
"""

from collections.abc import Callable, Mapping
from typing import Any, Never

from sweet_tv.errors import SerializationError

JsonMap = Mapping[str, Any]


def _fail(json: JsonMap, key: str, expected: str, owner: str | None) -> Never:
    where = key if owner is None else f"{owner}.{key}"
    raise SerializationError(
        f"expected {expected} at `{where}`, got {type(json.get(key)).__name__}"
    )


def require_int(json: JsonMap, key: str, *, owner: str | None = None) -> int:
    value = json.get(key)
    if isinstance(value, bool):
        return _fail(json, key, "int", owner)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return _fail(json, key, "int", owner)


def int_or(json: JsonMap, key: str, fallback: int = 0) -> int:
    value = json.get(key)
    if isinstance(value, bool):
        return fallback
    if isinstance(value, int):
        return value
    return int(value) if isinstance(value, float) else fallback


def str_or(json: JsonMap, key: str, fallback: str = "") -> str:
    value = json.get(key)
    return value if isinstance(value, str) else fallback


def str_or_none(json: JsonMap, key: str) -> str | None:
    value = json.get(key)
    return value if isinstance(value, str) and value else None


def text_or_none(json: JsonMap, key: str) -> str | None:
    """A string that is only whitespace is nothing, not a title."""
    value = str_or_none(json, key)
    return value.strip() or None if value else None


def bool_or(json: JsonMap, key: str, *, fallback: bool = False) -> bool:
    value = json.get(key)
    return value if isinstance(value, bool) else fallback


def map_or_none(json: JsonMap, key: str) -> JsonMap | None:
    value = json.get(key)
    return value if isinstance(value, Mapping) else None


def int_list(json: JsonMap, key: str) -> tuple[int, ...]:
    value = json.get(key)
    if not isinstance(value, list):
        return ()
    return tuple(item for item in value if isinstance(item, int) and not isinstance(item, bool))


def list_of[T](json: JsonMap, key: str, parse: Callable[[JsonMap], T]) -> tuple[T, ...]:
    value = json.get(key)
    if not isinstance(value, list):
        return ()
    return tuple(parse(item) for item in value if isinstance(item, Mapping))
