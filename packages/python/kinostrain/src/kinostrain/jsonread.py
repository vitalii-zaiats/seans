"""Tolerant readers used by every `from_json` in this package.

The `*_or_none` readers return `None` for a missing field, a JSON `null` or a
value of an unexpected type — the client stays usable when upstream grows or
loosens a field. The `require_*` readers raise `SerializationError` naming the
field, because a missing required field means the model can no longer be
trusted.
"""

from collections.abc import Callable, Mapping
from datetime import datetime
from typing import Any, Never

from kinostrain.errors import SerializationError

#: A decoded JSON object.
JsonMap = Mapping[str, Any]


def _fail(json: JsonMap, key: str, expected: str, owner: str | None) -> Never:
    where = key if owner is None else f"{owner}.{key}"
    got = type(json.get(key)).__name__
    raise SerializationError(f"expected {expected} at `{where}`, got {got}")


def require_str(json: JsonMap, key: str, *, owner: str | None = None) -> str:
    value = json.get(key)
    return value if isinstance(value, str) else _fail(json, key, "str", owner)


def str_or_none(json: JsonMap, key: str) -> str | None:
    value = json.get(key)
    return value if isinstance(value, str) else None


def require_int(json: JsonMap, key: str, *, owner: str | None = None) -> int:
    value = json.get(key)
    # `bool` is an `int` in Python and never what a numeric field means here.
    if isinstance(value, bool):
        return _fail(json, key, "int", owner)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return _fail(json, key, "int", owner)


def int_or_none(json: JsonMap, key: str) -> int | None:
    value = json.get(key)
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    return int(value) if isinstance(value, float) else None


def float_or_none(json: JsonMap, key: str) -> float | None:
    """A number upstream sends as either shape — `imdbMark` is `7` for some
    titles and `6.4` for others."""
    value = json.get(key)
    if isinstance(value, bool):
        return None
    return float(value) if isinstance(value, int | float) else None


def bool_or(json: JsonMap, key: str, *, fallback: bool = False) -> bool:
    value = json.get(key)
    return value if isinstance(value, bool) else fallback


def datetime_or_none(json: JsonMap, key: str) -> datetime | None:
    """Reads `2026-08-18T00:00:00+03:00` and the plain `2020-04-15` alike."""
    value = json.get(key)
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def map_or_none(json: JsonMap, key: str) -> JsonMap | None:
    value = json.get(key)
    return value if isinstance(value, Mapping) else None


def list_of[T](json: JsonMap, key: str, parse: Callable[[JsonMap], T]) -> tuple[T, ...]:
    """Maps a JSON array of objects, skipping entries that are not objects.

    Empty when the field is absent or not a list.
    """
    value = json.get(key)
    if not isinstance(value, list):
        return ()
    return tuple(parse(item) for item in value if isinstance(item, Mapping))


def list_or_none_of[T](
    json: JsonMap, key: str, parse: Callable[[JsonMap], T]
) -> tuple[T, ...] | None:
    """As `list_of`, but `None` rather than empty when the field is absent — so
    "no data" stays distinguishable from "empty collection"."""
    return list_of(json, key, parse) if isinstance(json.get(key), list) else None


def str_list(json: JsonMap, key: str) -> tuple[str, ...]:
    value = json.get(key)
    if not isinstance(value, list):
        return ()
    return tuple(item for item in value if isinstance(item, str))


def str_list_or_none(json: JsonMap, key: str) -> tuple[str, ...] | None:
    return str_list(json, key) if isinstance(json.get(key), list) else None
