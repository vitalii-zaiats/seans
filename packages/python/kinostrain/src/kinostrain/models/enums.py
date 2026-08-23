"""The two closed vocabularies the API uses."""

from enum import IntEnum, StrEnum


class ContentType(StrEnum):
    """The five content sections the API exposes.

    The value is what goes into the `type` query parameter and what the server
    echoes back in card and detail payloads.
    """

    MOVIE = "movie"
    SERIAL = "serial"
    CARTOON_MOVIE = "cartoon-movie"
    CARTOON_SERIES = "cartoon-series"
    ANIME = "anime"

    @property
    def slug(self) -> str:
        """Wire value, e.g. `cartoon-movie`."""
        return self.value

    @classmethod
    def try_parse(cls, slug: str | None) -> "ContentType | None":
        """The matching section, or `None` for anything unrecognised.

        Never raises: an API that grows a sixth section must not break parsing
        of the five known ones.
        """
        if slug is None:
            return None
        try:
            return cls(slug)
        except ValueError:
            return None


class Gender(IntEnum):
    """Gender code attached to people (cast, directors, `/persons`).

    Captured payloads only ever carry `0`, `1` and `2`; the mapping follows the
    TMDB convention the codes appear to come from. Anything else falls back to
    `UNSPECIFIED`.
    """

    UNSPECIFIED = 0
    FEMALE = 1
    MALE = 2

    @classmethod
    def from_code(cls, code: int | None) -> "Gender":
        if code is None:
            return cls.UNSPECIFIED
        try:
            return cls(code)
        except ValueError:
            return cls.UNSPECIFIED
